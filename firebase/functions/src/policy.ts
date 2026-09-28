import type { Criterion } from "./criteria";

// Deterministic mapping from a model assessment to verified / rejected / uncertain.
// Mirrors DisciplineCore/Verification/VerificationPolicy.swift. Both implementations run the
// shared vectors in Packages/DisciplineCore/Tests/DisciplineCoreTests/Fixtures/verification-policy-cases.json.

export type DecidedStatus = "verified" | "rejected" | "uncertain";

export interface Assessment {
  criteria: { id: string; passed: boolean }[];
  confidence: number;
  reason: string;
  flags: string[];
}

export interface CriterionResult {
  criterionId: string;
  name: string;
  passed: boolean;
}

export interface Decision {
  status: DecidedStatus;
  confidence: number;
  criteria: CriterionResult[];
  reason: string;
  flags: string[];
}

export const UNEXPECTED_CRITERION_FLAG = "unexpected_criterion";

export class MalformedResponseError extends Error {
  readonly code = "malformed_response";
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Parses and shape-checks the model's text output. Throws `MalformedResponseError`. */
export function parseAssessment(text: string): Assessment {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new MalformedResponseError("Response is not valid assessment JSON.");
  }
  if (
    !isObject(value) ||
    !Array.isArray(value.criteria) ||
    !value.criteria.every((c) => isObject(c) && typeof c.id === "string" && typeof c.passed === "boolean") ||
    typeof value.confidence !== "number" ||
    typeof value.reason !== "string" ||
    !Array.isArray(value.flags) ||
    !value.flags.every((f) => typeof f === "string")
  ) {
    throw new MalformedResponseError("Response is not valid assessment JSON.");
  }
  return value as unknown as Assessment;
}

export function decide(assessment: Assessment, criteria: Criterion[], threshold: number): Decision {
  const { confidence } = assessment;
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    throw new MalformedResponseError(`Confidence ${confidence} is outside [0, 1].`);
  }

  const answers = new Map<string, boolean>();
  for (const answer of assessment.criteria) {
    const existing = answers.get(answer.id);
    if (existing !== undefined && existing !== answer.passed) {
      throw new MalformedResponseError(`Criterion ${answer.id} was answered inconsistently.`);
    }
    answers.set(answer.id, answer.passed);
  }

  const results: CriterionResult[] = criteria.map((criterion) => {
    const passed = answers.get(criterion.id);
    if (passed === undefined) {
      throw new MalformedResponseError(`Criterion ${criterion.id} was not answered.`);
    }
    return { criterionId: criterion.id, name: criterion.name, passed };
  });

  const flags = [...assessment.flags];
  const known = new Set(criteria.map((c) => c.id));
  if ([...answers.keys()].some((id) => !known.has(id))) {
    flags.push(UNEXPECTED_CRITERION_FLAG);
  }

  let status: DecidedStatus;
  if (confidence < threshold) {
    status = "uncertain";
  } else {
    const required = new Set(criteria.filter((c) => c.isRequired).map((c) => c.id));
    status = results.every((r) => !required.has(r.criterionId) || r.passed) ? "verified" : "rejected";
  }

  return { status, confidence, criteria: results, reason: assessment.reason, flags };
}
