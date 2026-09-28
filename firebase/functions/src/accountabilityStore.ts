import { FieldValue, getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { isOpen, type ExpiryStore, type TaskState, type TaskStatus } from "./accountability";

export class FirestoreExpiryStore implements ExpiryStore {
  constructor(private readonly db: Firestore = getFirestore()) {}

  async findOverdueOpenTasks(now: Date, limit: number): Promise<TaskState[]> {
    // Requires the (status, deadline) composite index in firestore.indexes.json.
    const snapshot = await this.db
      .collection("accountabilityTasks")
      .where("status", "in", ["pending", "inProgress"])
      .where("deadline", "<", Timestamp.fromDate(now))
      .limit(limit)
      .get();
    return snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        status: data.status as TaskStatus,
        target: data.target as number,
        deadline: (data.deadline as Timestamp).toDate(),
        sourceCompletionId: data.sourceCompletionId as string,
      };
    });
  }

  async resolveIfOpen(taskId: string, status: TaskStatus, completionStatus: string, now: Date): Promise<boolean> {
    return this.db.runTransaction(async (tx) => {
      const taskRef = this.db.collection("accountabilityTasks").doc(taskId);
      const task = await tx.get(taskRef);
      if (!task.exists || !isOpen(task.get("status") as TaskStatus)) return false;

      tx.update(taskRef, {
        status,
        ...(status === "completed" ? { completedAt: Timestamp.fromDate(now) } : {}),
      });
      const completionRef = this.db.collection("habitCompletions").doc(task.get("sourceCompletionId") as string);
      tx.update(completionRef, { status: completionStatus, updatedAt: FieldValue.serverTimestamp() });
      return true;
    });
  }
}
