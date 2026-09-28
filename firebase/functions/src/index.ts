import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { randomUUID } from "node:crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as functionsV1 from "firebase-functions/v1";
import { getFirestore } from "firebase-admin/firestore";
import { refreshAllParticipants } from "./research/jobs";
import { dailyCsv, eventsCsv, type EventRow } from "./research/records";
import { assignCondition, deleteUserData, FirestoreResearchStore } from "./research/researchStore";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { applySessionsToTask, expireOverdueTasks } from "./accountability";
import { FirestoreExpiryStore } from "./accountabilityStore";
import { FirestoreSessionResolutionStore } from "./exerciseStore";
import { loadCatalog } from "./criteria";
import { FirestoreVerificationStore } from "./firestoreStore";
import { AnthropicVisionProvider, DEFAULT_ANTHROPIC_MODEL } from "./providers/anthropic";
import { runVerification, VerificationRequestError } from "./verify";

initializeApp();

// The provider API key lives only in Secret Manager: `firebase functions:secrets:set ANTHROPIC_API_KEY`.
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const verificationModel = defineString("VERIFICATION_MODEL", { default: DEFAULT_ANTHROPIC_MODEL });

const catalog = loadCatalog();

/**
 * Callable: verifies one piece of photo evidence. Input `{ evidenceId }`.
 * Returns the stored verification record with `timestamp` as epoch milliseconds.
 */
export const verifyEvidence = onCall(
  { secrets: [anthropicApiKey], timeoutSeconds: 120, memory: "512MiB", maxInstances: 10 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to verify evidence.");
    const evidenceId = (request.data as { evidenceId?: unknown } | undefined)?.evidenceId;
    if (typeof evidenceId !== "string" || !/^[A-Za-z0-9-]{1,64}$/.test(evidenceId)) {
      throw new HttpsError("invalid-argument", "A valid evidenceId is required.");
    }

    const provider = new AnthropicVisionProvider(new Anthropic({ apiKey: anthropicApiKey.value() }), verificationModel.value());
    try {
      const record = await runVerification(request.auth.uid, evidenceId, {
        store: new FirestoreVerificationStore(),
        provider,
        catalog,
        newId: randomUUID,
      });
      return { ...record, timestamp: record.timestamp.getTime() };
    } catch (error) {
      if (error instanceof VerificationRequestError) throw new HttpsError(error.code, error.message);
      throw new HttpsError("internal", "Verification failed unexpectedly.");
    }
  },
);

/**
 * Expires accountability tasks whose deadline passed without enough valid repetitions, and
 * marks the skipped occurrence as failed. Runs server-side so expiry can't be avoided by
 * keeping the app closed.
 */
export const expireAccountabilityTasks = onSchedule({ schedule: "every 15 minutes", timeoutSeconds: 300 }, async () => {
  const expired = await expireOverdueTasks(new FirestoreExpiryStore(), new Date());
  if (expired > 0) logger.info(`Expired ${expired} accountability task(s).`);
});

/**
 * When a camera exercise session is stored, recompute its task's progress and complete the
 * task (resolving the skipped occurrence) once valid repetitions reach the target.
 */
export const onExerciseSessionCreated = onDocumentCreated("exerciseSessions/{sessionId}", async (event) => {
  const taskId = event.data?.get("accountabilityTaskId");
  if (typeof taskId !== "string") return;
  const status = await applySessionsToTask(new FirestoreSessionResolutionStore(), taskId, new Date());
  logger.info(`Session ${event.params.sessionId} applied to task ${taskId}: ${status ?? "task not found"}`);
});

/**
 * Server-side experimental condition assignment (permuted blocks of 4) when a profile is
 * created. Replaces the client's provisional value; security rules make it immutable for clients.
 */
export const onUserProfileCreated = onDocumentCreated("users/{uid}", async (event) => {
  const condition = await assignCondition(getFirestore(), event.params.uid);
  if (condition) logger.info(`Assigned condition for new participant: ${condition}`);
});

/**
 * Daily research records for consenting participants: resolves recent history with the shared
 * day definition and writes `dailyRecords/{participantId}_{day}` (recent days are rewritten
 * while they may still change, e.g. pending verification).
 */
export const refreshDailyRecords = onSchedule({ schedule: "every day 04:00", timeZone: "UTC", timeoutSeconds: 540, memory: "1GiB" }, async () => {
  const result = await refreshAllParticipants(new FirestoreResearchStore(), new Date());
  logger.info(`Research records refreshed: ${result.records} record(s) for ${result.participants} participant(s).`);
});

/**
 * Researcher-only: anonymous CSV exports (daily records and completion events).
 * Requires the `researcher: true` custom claim.
 */
export const exportResearchCsv = onCall({ timeoutSeconds: 300, memory: "1GiB" }, async (request) => {
  if (request.auth?.token.researcher !== true) {
    throw new HttpsError("permission-denied", "Researcher access required.");
  }
  const store = new FirestoreResearchStore();
  const now = new Date();
  const records = await store.allDailyRecords();
  const outcomes = new Map(records.map((r) => [`${r.participantId}_${r.day}`, r.outcome]));
  const events: EventRow[] = [];
  for (const participant of await store.participants()) {
    if (!participant.consented) continue;
    const data = await store.load(participant.uid, "2000-01-01");
    const categories = new Map(data.habits.map((h) => [h.id, h.category ?? "custom"]));
    const tasks = new Map(data.tasks.map((t) => [t.id, t]));
    for (const completion of data.completions) {
      events.push({
        participantId: participant.participantId,
        condition: participant.condition,
        completion,
        habitCategory: categories.get(completion.habitId) ?? "custom",
        confidence: completion.verificationId ? data.confidences.get(completion.verificationId) : undefined,
        task: completion.accountabilityTaskId ? tasks.get(completion.accountabilityTaskId) : undefined,
        dayOutcome: outcomes.get(`${participant.participantId}_${completion.day}`),
        now,
      });
    }
  }
  return { daily: dailyCsv(records), events: eventsCsv(events), generatedAt: now.getTime() };
});

/** Deletes all of a participant's data, photos and research records when their account is deleted. */
export const onUserDeleted = functionsV1.auth.user().onDelete(async (user) => {
  await deleteUserData(getFirestore(), user.uid);
  logger.info("Deleted data for a removed account.");
});
