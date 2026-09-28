import { RESOLVER_VERSION, type CompletionStatus, type StreakSummary, type TaskStatus } from "./resolver";

export type Condition = "manual" | "aiAssisted";

/** Mirrors the Swift `DailyRecord`. Keyed by pseudonymous participant id; counts only. */
export interface DailyRecord {
  participantId: string;
  challengeId: string | null;
  day: string;
  trackingCondition: Condition;
  requiredHabits: number;
  completedHabits: number;
  skippedHabits: number;
  verifiedHabits: number;
  rejectedHabits: number;
  uncertainHabits: number;
  selfReportedHabits: number;
  accountabilityTasks: number;
  accountabilityTasksCompleted: number;
  accountabilityTasksFailed: number;
  verificationCount: number;
  verificationConfidenceSum: number;
  outcome: string;
  streakBefore: number;
  streakAfter: number;
  resolverVersion: string;
}

export interface RecordHabit { id: string; challengeId?: string | null; category?: string }
export interface RecordCompletion {
  id?: string;
  habitId: string;
  day: string;
  status: CompletionStatus;
  method?: string;
  quantity?: number;
  verificationId?: string | null;
  accountabilityTaskId?: string | null;
}
export interface RecordTask { id: string; day: string; sourceHabitId: string; status: TaskStatus; deadline: Date; type?: string; target?: number }

const effectiveTaskStatus = (task: RecordTask, now: Date): TaskStatus =>
  (task.status === "pending" || task.status === "inProgress") && now > task.deadline ? "expired" : task.status;

/** Mirrors `DailyRecordBuilder.build`: one record per day with commitments in effect. */
export function buildDailyRecords(
  participantId: string,
  condition: Condition,
  summary: StreakSummary,
  habits: RecordHabit[],
  completions: RecordCompletion[],
  tasks: RecordTask[],
  confidences: Map<string, number>,
  now: Date,
): DailyRecord[] {
  const records: DailyRecord[] = [];
  for (const streakDay of summary.days) {
    const { resolution } = streakDay;
    if (!resolution.hasCommitments) continue;
    const scope = new Set(habits.filter((h) => streakDay.challengeId === null || h.challengeId === streakDay.challengeId).map((h) => h.id));
    const events = completions.filter((c) => c.day === resolution.day && scope.has(c.habitId));
    const dayTasks = tasks.filter((t) => t.day === resolution.day && scope.has(t.sourceHabitId));
    const confidenceValues = events
      .map((c) => (c.verificationId ? confidences.get(c.verificationId) : undefined))
      .filter((v): v is number => typeof v === "number");
    const count = (status: CompletionStatus) => events.filter((c) => c.status === status).length;

    records.push({
      participantId,
      challengeId: streakDay.challengeId,
      day: resolution.day,
      trackingCondition: condition,
      requiredHabits: resolution.due.length,
      completedHabits: resolution.due.filter((d) => d.resolution === "resolved").length,
      skippedHabits: events.filter((c) => c.method === "accountabilityExercise").length,
      verifiedHabits: count("verified"),
      rejectedHabits: count("rejected"),
      uncertainHabits: count("uncertain"),
      selfReportedHabits: count("selfReported"),
      accountabilityTasks: dayTasks.length,
      accountabilityTasksCompleted: dayTasks.filter((t) => t.status === "completed").length,
      accountabilityTasksFailed: dayTasks.filter((t) => ["failed", "expired"].includes(effectiveTaskStatus(t, now))).length,
      verificationCount: confidenceValues.length,
      verificationConfidenceSum: confidenceValues.reduce((a, b) => a + b, 0),
      outcome: resolution.outcome,
      streakBefore: streakDay.streakBefore,
      streakAfter: streakDay.streakAfter,
      resolverVersion: RESOLVER_VERSION,
    });
  }
  return records;
}

// ---------- CSV (anonymous) ----------

/** Identical to `ResearchCSV.dailyHeader` in Swift. */
export const DAILY_HEADER = [
  "participant_id", "date", "condition", "challenge_id", "required_habits", "completed_habits",
  "self_reported", "verified", "rejected", "uncertain", "skipped", "accountability_tasks",
  "accountability_completed", "accountability_failed", "verification_count",
  "mean_verification_confidence", "day_outcome", "day_successful", "streak_before", "streak_after",
  "resolver_version",
];

export const EVENTS_HEADER = [
  "participant_id", "date", "condition", "habit_id", "habit_category", "completion_status", "completion_method",
  "quantity", "verification_status", "verification_confidence", "accountability_task_type",
  "accountability_target", "accountability_status", "day_outcome", "day_successful",
];

const escape = (field: string) => (/[",\r\n]/.test(field) ? `"${field.replace(/"/g, '""')}"` : field);
const encode = (header: string[], rows: string[][]) =>
  [header, ...rows].map((row) => row.map(escape).join(",")).join("\n") + "\n";

export function dailyCsv(records: DailyRecord[]): string {
  const rows = [...records]
    .sort((a, b) => (a.participantId === b.participantId ? a.day.localeCompare(b.day) : a.participantId < b.participantId ? -1 : 1))
    .map((r) => [
      r.participantId, r.day, r.trackingCondition, r.challengeId ?? "",
      `${r.requiredHabits}`, `${r.completedHabits}`, `${r.selfReportedHabits}`, `${r.verifiedHabits}`,
      `${r.rejectedHabits}`, `${r.uncertainHabits}`, `${r.skippedHabits}`, `${r.accountabilityTasks}`,
      `${r.accountabilityTasksCompleted}`, `${r.accountabilityTasksFailed}`, `${r.verificationCount}`,
      r.verificationCount > 0 ? (r.verificationConfidenceSum / r.verificationCount).toFixed(4) : "",
      r.outcome, r.outcome === "successful" ? "1" : "0", `${r.streakBefore}`, `${r.streakAfter}`, r.resolverVersion,
    ]);
  return encode(DAILY_HEADER, rows);
}

export interface EventRow {
  participantId: string;
  condition: Condition;
  completion: RecordCompletion;
  habitCategory: string;
  confidence?: number;
  task?: RecordTask;
  dayOutcome?: string;
  now: Date;
}

/** Completion-level export. Habit ids are random UUIDs; habit names are never exported. */
export function eventsCsv(events: EventRow[]): string {
  const verificationStatus = (c: RecordCompletion) =>
    c.method === "photoVerification"
      ? (["verified", "rejected", "uncertain", "pendingVerification"].includes(c.status) ? c.status : "")
      : "";
  const rows = [...events]
    .sort((a, b) => (a.participantId === b.participantId ? a.completion.day.localeCompare(b.completion.day) : a.participantId < b.participantId ? -1 : 1))
    .map((e) => [
      e.participantId, e.completion.day, e.condition, e.completion.habitId, e.habitCategory, e.completion.status,
      e.completion.method ?? "", `${e.completion.quantity ?? 1}`, verificationStatus(e.completion),
      e.confidence !== undefined ? e.confidence.toFixed(4) : "",
      e.task?.type ?? "", e.task?.target !== undefined ? `${e.task.target}` : "",
      e.task ? effectiveTaskStatus(e.task, e.now) : "",
      e.dayOutcome ?? "", e.dayOutcome === "successful" ? "1" : e.dayOutcome ? "0" : "",
    ]);
  return encode(EVENTS_HEADER, rows);
}
