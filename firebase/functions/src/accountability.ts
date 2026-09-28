// Accountability task lifecycle. Mirrors DisciplineCore/Accountability/AccountabilityPlanner.swift
// (AccountabilityLifecycle): a task is completed when valid repetitions from sessions finished
// before the deadline reach the target, and expired when its deadline passes first.

export type TaskStatus = "pending" | "inProgress" | "completed" | "failed" | "expired";

export interface TaskState {
  id: string;
  status: TaskStatus;
  target: number;
  deadline: Date;
  sourceCompletionId: string;
}

export interface SessionState {
  accountabilityTaskId: string;
  validReps: number;
  completedAt: Date | null;
}

export const isOpen = (status: TaskStatus) => status === "pending" || status === "inProgress";

export function validRepetitions(task: TaskState, sessions: SessionState[]): number {
  return sessions
    .filter((s) => s.accountabilityTaskId === task.id && s.completedAt !== null && s.completedAt <= task.deadline)
    .reduce((sum, s) => sum + s.validReps, 0);
}

export function evaluateTask(task: TaskState, sessions: SessionState[], now: Date): TaskStatus {
  if (!isOpen(task.status)) return task.status;
  if (validRepetitions(task, sessions) >= task.target) return "completed";
  if (now > task.deadline) return "expired";
  return task.status;
}

export function completionStatusFor(status: TaskStatus): "resolved" | "failed" | "accountabilityRequired" {
  switch (status) {
    case "completed":
      return "resolved";
    case "failed":
    case "expired":
      return "failed";
    default:
      return "accountabilityRequired";
  }
}

/** Persistence boundary for the expiry job; Admin SDK implementation in accountabilityStore.ts. */
export interface ExpiryStore {
  findOverdueOpenTasks(now: Date, limit: number): Promise<TaskState[]>;
  /**
   * Transactionally re-reads the task and, only if it is still open, writes the task status
   * and its skipped occurrence's completion status. Returns false if it was no longer open.
   */
  resolveIfOpen(taskId: string, status: TaskStatus, completionStatus: string, now: Date): Promise<boolean>;
}

/** Expires every overdue open task (in batches of `limit`). Returns the number expired. */
export async function expireOverdueTasks(store: ExpiryStore, now: Date, limit = 200): Promise<number> {
  let expired = 0;
  for (;;) {
    const overdue = await store.findOverdueOpenTasks(now, limit);
    if (overdue.length === 0) return expired;
    let changed = 0;
    for (const task of overdue) {
      if (evaluateTask(task, [], now) !== "expired") continue;
      if (await store.resolveIfOpen(task.id, "expired", completionStatusFor("expired"), now)) changed += 1;
    }
    expired += changed;
    if (overdue.length < limit || changed === 0) return expired;
  }
}

/** Persistence boundary for applying exercise sessions to their task. */
export interface SessionResolutionStore {
  getTask(taskId: string): Promise<(TaskState & { userId: string }) | null>;
  /**
   * Sessions for the task. `completedAt` must be the EARLIER of the client-reported end time
   * and the server's receive time, so a session can't be backdated to beat the deadline.
   */
  getSessions(taskId: string): Promise<(SessionState & { userId: string })[]>;
  /** Transactionally: if the task is still open, set progress and, when given, the new status. */
  applyProgress(taskId: string, progress: number, status: TaskStatus | null, completionStatus: string | null, now: Date): Promise<boolean>;
}

/**
 * Re-evaluates a task after one of its exercise sessions is stored: updates progress (valid
 * reps before the deadline) and completes the task — resolving the skipped occurrence — once
 * the target is reached. Returns the resulting status, or null if the task doesn't exist.
 */
export async function applySessionsToTask(store: SessionResolutionStore, taskId: string, now: Date): Promise<TaskStatus | null> {
  const task = await store.getTask(taskId);
  if (!task) return null;
  // Only the task owner's sessions count (also enforced by security rules).
  const sessions = (await store.getSessions(taskId)).filter((s) => s.userId === task.userId);
  const progress = validRepetitions(task, sessions);
  const status = evaluateTask(task, sessions, now);
  const changed = status !== task.status ? status : null;
  await store.applyProgress(taskId, progress, changed, changed ? completionStatusFor(changed) : null, now);
  return status;
}
