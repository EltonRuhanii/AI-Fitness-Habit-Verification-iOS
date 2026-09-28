import { FieldValue, getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { isOpen, type SessionResolutionStore, type SessionState, type TaskState, type TaskStatus } from "./accountability";

export class FirestoreSessionResolutionStore implements SessionResolutionStore {
  constructor(private readonly db: Firestore = getFirestore()) {}

  async getTask(taskId: string): Promise<(TaskState & { userId: string }) | null> {
    const snap = await this.db.collection("accountabilityTasks").doc(taskId).get();
    if (!snap.exists) return null;
    return {
      id: snap.id,
      userId: snap.get("userId") as string,
      status: snap.get("status") as TaskStatus,
      target: snap.get("target") as number,
      deadline: (snap.get("deadline") as Timestamp).toDate(),
      sourceCompletionId: snap.get("sourceCompletionId") as string,
    };
  }

  async getSessions(taskId: string): Promise<(SessionState & { userId: string })[]> {
    const snapshot = await this.db.collection("exerciseSessions").where("accountabilityTaskId", "==", taskId).get();
    return snapshot.docs.map((doc) => {
      const received = doc.createTime.toDate();
      const reported = (doc.get("completedAt") as Timestamp | undefined)?.toDate();
      const completedAt = reported && reported < received ? reported : received;
      return {
        accountabilityTaskId: taskId,
        userId: doc.get("userId") as string,
        validReps: Math.max(0, Math.floor(Number(doc.get("validReps")) || 0)),
        completedAt,
      } satisfies SessionState & { userId: string };
    });
  }

  async applyProgress(taskId: string, progress: number, status: TaskStatus | null, completionStatus: string | null, now: Date): Promise<boolean> {
    return this.db.runTransaction(async (tx) => {
      const taskRef = this.db.collection("accountabilityTasks").doc(taskId);
      const task = await tx.get(taskRef);
      if (!task.exists || !isOpen(task.get("status") as TaskStatus)) return false;
      tx.update(taskRef, {
        progress,
        ...(status ? { status } : {}),
        ...(status === "completed" ? { completedAt: Timestamp.fromDate(now) } : {}),
      });
      if (status && completionStatus) {
        tx.update(this.db.collection("habitCompletions").doc(task.get("sourceCompletionId") as string), {
          status: completionStatus,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return true;
    });
  }
}
