import assert from "node:assert/strict";
import { test } from "node:test";
import {
  applySessionsToTask,
  completionStatusFor,
  evaluateTask,
  expireOverdueTasks,
  type ExpiryStore,
  type SessionState,
  type TaskState,
} from "../accountability";

const accepted = new Date("2026-09-28T10:00:00Z");
const deadline = new Date("2026-09-29T10:00:00Z");
const task = (overrides: Partial<TaskState> = {}): TaskState => ({
  id: "t1", status: "pending", target: 50, deadline, sourceCompletionId: "c1", ...overrides,
});
const session = (validReps: number, completedAt: Date | null, taskId = "t1"): SessionState => ({
  accountabilityTaskId: taskId, validReps, completedAt,
});

test("completes when valid reps before the deadline reach the target", () => {
  const during = new Date(accepted.getTime() + 3_600_000);
  assert.equal(evaluateTask(task(), [session(30, during)], during), "pending");
  assert.equal(evaluateTask(task(), [session(30, during), session(20, during)], during), "completed");
  assert.equal(completionStatusFor("completed"), "resolved");
});

test("reps after the deadline don't count; the task expires", () => {
  const late = new Date(deadline.getTime() + 60_000);
  assert.equal(evaluateTask(task(), [session(50, late)], late), "expired");
  assert.equal(completionStatusFor("expired"), "failed");
});

test("unfinished sessions and other tasks' sessions are ignored", () => {
  const during = new Date(accepted.getTime() + 60_000);
  assert.equal(evaluateTask(task(), [session(50, null), session(50, during, "other")], during), "pending");
});

test("terminal states are final", () => {
  const late = new Date(deadline.getTime() + 60_000);
  assert.equal(evaluateTask(task({ status: "completed" }), [], late), "completed");
  assert.equal(evaluateTask(task({ status: "expired" }), [session(50, accepted)], late), "expired");
});

class FakeExpiryStore implements ExpiryStore {
  constructor(public tasks: TaskState[]) {}
  resolved: { id: string; status: string; completion: string }[] = [];
  async findOverdueOpenTasks(now: Date, limit: number) {
    return this.tasks.filter((t) => (t.status === "pending" || t.status === "inProgress") && t.deadline < now).slice(0, limit);
  }
  async resolveIfOpen(taskId: string, status: TaskState["status"], completionStatus: string) {
    const t = this.tasks.find((x) => x.id === taskId);
    if (!t || !(t.status === "pending" || t.status === "inProgress")) return false;
    t.status = status;
    this.resolved.push({ id: taskId, status, completion: completionStatus });
    return true;
  }
}

test("expiry job expires only overdue open tasks and fails their occurrences, across batches", async () => {
  const now = new Date(deadline.getTime() + 1);
  const store = new FakeExpiryStore([
    task({ id: "overdue1" }),
    task({ id: "overdue2", status: "inProgress" }),
    task({ id: "overdue3" }),
    task({ id: "future", deadline: new Date(now.getTime() + 3_600_000) }),
    task({ id: "done", status: "completed" }),
  ]);
  const count = await expireOverdueTasks(store, now, 2);
  assert.equal(count, 3);
  assert.deepEqual(store.resolved.map((r) => r.id).sort(), ["overdue1", "overdue2", "overdue3"]);
  assert.ok(store.resolved.every((r) => r.status === "expired" && r.completion === "failed"));
  assert.equal(store.tasks.find((t) => t.id === "future")?.status, "pending");
});

class FakeSessionStore {
  constructor(
    public task: (TaskState & { userId: string }) | null,
    public sessions: (SessionState & { userId: string })[],
  ) {}
  applied: { progress: number; status: string | null; completion: string | null }[] = [];
  async getTask() { return this.task; }
  async getSessions() { return this.sessions; }
  async applyProgress(_id: string, progress: number, status: TaskState["status"] | null, completion: string | null) {
    this.applied.push({ progress, status, completion });
    if (this.task && status) this.task.status = status;
    return true;
  }
}

test("session application: partial progress, then completion resolves the occurrence", async () => {
  const during = new Date(accepted.getTime() + 3_600_000);
  const store = new FakeSessionStore({ ...task(), userId: "alice" }, [{ ...session(30, during), userId: "alice" }]);
  assert.equal(await applySessionsToTask(store, "t1", during), "pending");
  assert.deepEqual(store.applied[0], { progress: 30, status: null, completion: null });

  store.sessions.push({ ...session(20, during), userId: "alice" });
  assert.equal(await applySessionsToTask(store, "t1", during), "completed");
  assert.deepEqual(store.applied[1], { progress: 50, status: "completed", completion: "resolved" });
});

test("session application ignores other users' sessions and missing tasks", async () => {
  const during = new Date(accepted.getTime() + 60_000);
  const store = new FakeSessionStore({ ...task(), userId: "alice" }, [{ ...session(50, during), userId: "mallory" }]);
  assert.equal(await applySessionsToTask(store, "t1", during), "pending");
  assert.equal(store.applied[0].progress, 0);
  assert.equal(await applySessionsToTask(new FakeSessionStore(null, []), "missing", during), null);
});

test("a session received after the deadline expires the task instead of completing it", async () => {
  const late = new Date(deadline.getTime() + 60_000);
  const store = new FakeSessionStore({ ...task(), userId: "alice" }, [{ ...session(50, late), userId: "alice" }]);
  assert.equal(await applySessionsToTask(store, "t1", late), "expired");
  assert.deepEqual(store.applied[0], { progress: 0, status: "expired", completion: "failed" });
});
