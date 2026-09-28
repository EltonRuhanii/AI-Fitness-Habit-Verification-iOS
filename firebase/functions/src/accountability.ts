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
