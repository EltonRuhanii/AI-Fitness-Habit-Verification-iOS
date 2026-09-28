import { criteriaFor, type CriteriaCatalog } from "./criteria";
import { decide, MalformedResponseError, parseAssessment, type CriterionResult } from "./policy";
import { assessmentSchema, buildUserText, PROMPT_REVISION, SYSTEM_PROMPT } from "./prompt";
import { ProviderError, type VisionProvider } from "./providers/types";

export const MAX_ATTEMPTS_PER_EVIDENCE = 3;

export type VerificationStatus = "verified" | "rejected" | "uncertain" | "error";

/** Mirrors the Swift `VerificationResult` model. Written once; never updated. */
export interface VerificationRecord {
  id: string;
  userId: string;
  habitId: string;
  evidenceId: string;
  timestamp: Date;
  provider: string;
  model: string;
  promptVersion: string;
  criteria: CriterionResult[];
  status: VerificationStatus;
  confidence: number | null;
  confidenceThreshold: number;
  reason: string;
  flags: string[];
  processingTimeMs: number;
  errorCode?: string;
}

export interface EvidenceDoc {
  id: string;
  userId: string;
  habitId: string;
  completionId: string;
  storagePath: string;
  verificationStatus: string;
  verificationResultId?: string;
}

export interface HabitDoc {
  id: string;
  userId: string;
  name: string;
  description: string;
  category: string;
  challengeId?: string;
}

/** Persistence boundary, implemented with the Admin SDK in `firestoreStore.ts` and faked in tests. */
export interface VerificationStore {
  getEvidence(id: string): Promise<EvidenceDoc | null>;
  getHabit(id: string): Promise<HabitDoc | null>;
  getVerification(id: string): Promise<VerificationRecord | null>;
  /** Challenge-specific threshold, or null to use the catalog default. */
  getChallengeThreshold(challengeId: string): Promise<number | null>;
  countAttempts(evidenceId: string): Promise<number>;
  downloadImage(storagePath: string): Promise<Buffer>;
  /** Atomically: create the verification, update the evidence, and update the completion. */
  commit(record: VerificationRecord, evidence: EvidenceDoc, completionStatus: "verified" | "rejected" | "uncertain" | null): Promise<void>;
}

export type VerificationErrorCode = "not-found" | "permission-denied" | "resource-exhausted" | "failed-precondition";

/** Request-level failure (nothing recorded). Mapped to an HttpsError by the callable wrapper. */
export class VerificationRequestError extends Error {
  constructor(readonly code: VerificationErrorCode, message: string) {
    super(message);
  }
}

export interface VerificationDeps {
  store: VerificationStore;
  provider: VisionProvider;
  catalog: CriteriaCatalog;
  newId: () => string;
  now?: () => Date;
}

const DECIDED = new Set(["verified", "rejected", "uncertain"]);

/**
 * Runs one verification attempt for `evidenceId` on behalf of `uid`.
 *
 * Every attempt that reaches the provider is recorded — including failures (status `error`
 * with an `errorCode`) — so the research data shows pipeline reliability, not just outcomes.
 * Already-decided evidence returns its existing result without calling the provider again.
 */
export async function runVerification(uid: string, evidenceId: string, deps: VerificationDeps): Promise<VerificationRecord> {
  const { store, provider, catalog } = deps;
  const now = deps.now ?? (() => new Date());

  const evidence = await store.getEvidence(evidenceId);
  if (!evidence) throw new VerificationRequestError("not-found", "Evidence not found.");
  if (evidence.userId !== uid || !evidence.storagePath.startsWith(`evidence/${uid}/`)) {
    throw new VerificationRequestError("permission-denied", "You can only verify your own evidence.");
  }

  if (DECIDED.has(evidence.verificationStatus) && evidence.verificationResultId) {
    const existing = await store.getVerification(evidence.verificationResultId);
    if (existing) return existing;
  }

  if ((await store.countAttempts(evidenceId)) >= MAX_ATTEMPTS_PER_EVIDENCE) {
    throw new VerificationRequestError("resource-exhausted", "This evidence has reached the maximum number of verification attempts.");
  }

  const habit = await store.getHabit(evidence.habitId);
  if (!habit || habit.userId !== uid) throw new VerificationRequestError("failed-precondition", "The habit for this evidence no longer exists.");

  const criteria = criteriaFor(catalog, habit.category);
  const threshold = (habit.challengeId ? await store.getChallengeThreshold(habit.challengeId) : null) ?? catalog.defaultConfidenceThreshold;
  const started = now().getTime();

  const base = {
    id: deps.newId(),
    userId: uid,
    habitId: habit.id,
    evidenceId,
    provider: provider.name,
    promptVersion: `${catalog.version}/${PROMPT_REVISION}`,
    confidenceThreshold: threshold,
  };

  let record: VerificationRecord;
  try {
    const image = await store.downloadImage(evidence.storagePath);
    const response = await provider.assess({
      image,
      mediaType: "image/jpeg",
      system: SYSTEM_PROMPT,
      userText: buildUserText(habit, criteria),
      schema: assessmentSchema(criteria, catalog.flags),
    });
    const decision = decide(parseAssessment(response.text), criteria, threshold);
    record = {
      ...base,
      model: response.model,
      timestamp: now(),
      criteria: decision.criteria,
      status: decision.status,
      confidence: decision.confidence,
      reason: decision.reason,
      flags: decision.flags,
      processingTimeMs: now().getTime() - started,
    };
  } catch (error) {
    const errorCode =
      error instanceof ProviderError ? error.code : error instanceof MalformedResponseError ? error.code : "internal_error";
    record = {
      ...base,
      model: provider.model,
      timestamp: now(),
      criteria: [],
      status: "error",
      confidence: null,
      reason: error instanceof Error ? error.message : "Verification failed.",
      flags: [],
      processingTimeMs: now().getTime() - started,
      errorCode,
    };
  }

  // Errors leave the completion as pendingVerification so the participant can retry.
  await store.commit(record, evidence, record.status === "error" ? null : record.status);
  return record;
}
