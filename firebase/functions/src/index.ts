import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { randomUUID } from "node:crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { expireOverdueTasks } from "./accountability";
import { FirestoreExpiryStore } from "./accountabilityStore";
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
