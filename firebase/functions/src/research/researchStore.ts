import { getFirestore, Timestamp, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { assignForDesign, initialAssignmentState, STUDY_DESIGN, type AssignmentState } from "./assignment";
import type { Participant, ParticipantData, ResearchStore } from "./jobs";
import type { Condition, DailyRecord, UsabilityResponse } from "./records";
import { DEFAULT_RULES, type ChallengeInput, type Rules } from "./resolver";

const toDate = (value: unknown): Date | undefined => (value instanceof Timestamp ? value.toDate() : undefined);

export class FirestoreResearchStore implements ResearchStore {
  constructor(private readonly db: Firestore = getFirestore()) {}

  async participants(): Promise<Participant[]> {
    const snapshot = await this.db.collection("users").get();
    return snapshot.docs
      .filter((doc) => typeof doc.get("participantId") === "string")
      .map((doc) => ({
        uid: doc.id,
        participantId: doc.get("participantId") as string,
        condition: doc.get("trackingCondition") as Condition,
        timeZone: (doc.get("timeZone") as string | undefined) ?? "UTC",
        consented: doc.get("researchConsentAt") != null,
      }));
  }

  async load(uid: string, since: string): Promise<ParticipantData> {
    const [habits, completions, tasks, challenges, verifications] = await Promise.all([
      this.db.collection("habits").where("userId", "==", uid).get(),
      this.db.collection("habitCompletions").where("userId", "==", uid).where("day", ">=", since).get(),
      this.db.collection("accountabilityTasks").where("userId", "==", uid).get(),
      this.db.collection("challenges").where("ownerId", "==", uid).get(),
      this.db.collection("verifications").where("userId", "==", uid).get(),
    ]);
    const confidences = new Map<string, number>();
    for (const doc of verifications.docs) {
      const confidence = doc.get("confidence");
      if (typeof confidence === "number" && doc.get("status") !== "error") confidences.set(doc.id, confidence);
    }
    return {
      habits: habits.docs.map((d) => d.data() as DocumentData).map((h) => ({
        id: h.id, challengeId: h.challengeId ?? null, frequency: h.frequency, unit: h.unit, targetCount: h.targetCount,
        scheduledWeekdays: h.scheduledWeekdays ?? [], startDate: h.startDate, endDate: h.endDate ?? null,
        isRequired: h.isRequired !== false, isActive: h.isActive !== false, category: h.category,
      })),
      completions: completions.docs.map((d) => d.data()).map((c) => ({
        id: c.id, habitId: c.habitId, day: c.day, status: c.status, method: c.method, quantity: c.quantity ?? 1,
        verificationId: c.verificationId ?? null, accountabilityTaskId: c.accountabilityTaskId ?? null,
      })),
      tasks: tasks.docs.map((d) => d.data()).map((t) => ({
        id: t.id, day: t.day, sourceHabitId: t.sourceHabitId, status: t.status, type: t.type, target: t.target,
        deadline: toDate(t.deadline) ?? new Date(0),
      })),
      challenges: challenges.docs.map((d) => d.data()).map((c): ChallengeInput => ({
        id: c.id, status: c.status, startDate: c.startDate, endDate: c.endDate, createdAt: toDate(c.createdAt),
        rules: { ...DEFAULT_RULES, ...(c.rules as Partial<Rules>) },
      })),
      confidences,
    };
  }

  async existingRecordDays(participantId: string, since: string): Promise<Set<string>> {
    const snapshot = await this.db.collection("dailyRecords")
      .where("participantId", "==", participantId).where("day", ">=", since).select("day").get();
    return new Set(snapshot.docs.map((d) => d.get("day") as string));
  }

  async writeRecords(records: DailyRecord[]): Promise<void> {
    const writer = this.db.bulkWriter();
    for (const record of records) {
      writer.set(this.db.collection("dailyRecords").doc(`${record.participantId}_${record.day}`), {
        ...record,
        updatedAt: Timestamp.now(),
      });
    }
    await writer.close();
  }

  async allDailyRecords(): Promise<DailyRecord[]> {
    const snapshot = await this.db.collection("dailyRecords").get();
    return snapshot.docs.map((d) => d.data() as DailyRecord);
  }

  async allUsabilityResponses(): Promise<UsabilityResponse[]> {
    const snapshot = await this.db.collection("usabilityResponses").get();
    return snapshot.docs.map((d) => {
      const data = d.data();
      const submittedAt = data.submittedAt instanceof Timestamp ? data.submittedAt.toDate() : new Date(data.submittedAt);
      return { ...data, submittedAt } as UsabilityResponse;
    });
  }
}

/** Assigns the experimental condition for a new profile (idempotent). */
export async function assignCondition(db: Firestore, uid: string, random: () => number = Math.random): Promise<Condition | null> {
  const userRef = db.collection("users").doc(uid);
  const stateRef = db.collection("research").doc("assignment");
  return db.runTransaction(async (tx) => {
    const [user, stateSnap] = await Promise.all([tx.get(userRef), tx.get(stateRef)]);
    if (!user.exists || user.get("conditionAssignedBy")) return null;
    const state = (stateSnap.exists ? stateSnap.data() : initialAssignmentState()) as AssignmentState;
    const next = assignForDesign(STUDY_DESIGN, state, random);
    tx.set(stateRef, next.state);
    tx.update(userRef, {
      trackingCondition: next.condition,
      conditionAssignedBy: next.method,
      conditionAssignedAt: Timestamp.now(),
    });
    return next.condition;
  });
}

/** Deletes everything belonging to a deleted account, including its research records. */
export async function deleteUserData(db: Firestore, uid: string): Promise<void> {
  const user = await db.collection("users").doc(uid).get();
  const participantId = user.get("participantId") as string | undefined;
  const writer = db.bulkWriter();
  const byOwner: [string, string][] = [
    ["habits", "userId"], ["habitCompletions", "userId"], ["evidence", "userId"], ["verifications", "userId"],
    ["accountabilityTasks", "userId"], ["exerciseSessions", "userId"], ["challenges", "ownerId"],
  ];
  for (const [collection, field] of byOwner) {
    const snapshot = await db.collection(collection).where(field, "==", uid).get();
    snapshot.docs.forEach((doc) => writer.delete(doc.ref));
  }
  if (participantId) {
    const records = await db.collection("dailyRecords").where("participantId", "==", participantId).get();
    records.docs.forEach((doc) => writer.delete(doc.ref));
    const usability = await db.collection("usabilityResponses").where("participantId", "==", participantId).get();
    usability.docs.forEach((doc) => writer.delete(doc.ref));
  }
  writer.delete(db.collection("users").doc(uid));
  await writer.close();
  await getStorage().bucket().deleteFiles({ prefix: `evidence/${uid}/` });
}

