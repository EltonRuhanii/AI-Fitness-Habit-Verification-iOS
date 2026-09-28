import { FieldValue, getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type { EvidenceDoc, HabitDoc, VerificationRecord, VerificationStore } from "./verify";

/** Admin SDK implementation of the verification persistence boundary. */
export class FirestoreVerificationStore implements VerificationStore {
  constructor(private readonly db: Firestore = getFirestore()) {}

  async getEvidence(id: string): Promise<EvidenceDoc | null> {
    const snap = await this.db.collection("evidence").doc(id).get();
    return snap.exists ? (snap.data() as EvidenceDoc) : null;
  }

  async getHabit(id: string): Promise<HabitDoc | null> {
    const snap = await this.db.collection("habits").doc(id).get();
    return snap.exists ? (snap.data() as HabitDoc) : null;
  }

  async getVerification(id: string): Promise<VerificationRecord | null> {
    const snap = await this.db.collection("verifications").doc(id).get();
    if (!snap.exists) return null;
    const data = snap.data() as Omit<VerificationRecord, "timestamp"> & { timestamp: Timestamp };
    return { ...data, timestamp: data.timestamp.toDate() };
  }

  async getChallengeThreshold(challengeId: string): Promise<number | null> {
    const snap = await this.db.collection("challenges").doc(challengeId).get();
    const value = snap.get("rules.confidenceThreshold");
    return typeof value === "number" ? value : null;
  }

  async countAttempts(evidenceId: string): Promise<number> {
    const result = await this.db.collection("verifications").where("evidenceId", "==", evidenceId).count().get();
    return result.data().count;
  }

  async downloadImage(storagePath: string): Promise<Buffer> {
    const [buffer] = await getStorage().bucket().file(storagePath).download();
    return buffer;
  }

  async commit(record: VerificationRecord, evidence: EvidenceDoc, completionStatus: "verified" | "rejected" | "uncertain" | null): Promise<void> {
    const batch = this.db.batch();
    const { errorCode, ...rest } = record;
    batch.create(this.db.collection("verifications").doc(record.id), {
      ...rest,
      ...(errorCode ? { errorCode } : {}),
      timestamp: Timestamp.fromDate(record.timestamp),
    });
    batch.update(this.db.collection("evidence").doc(evidence.id), {
      verificationStatus: record.status,
      verificationResultId: record.id,
    });
    const completion = this.db.collection("habitCompletions").doc(evidence.completionId);
    batch.update(completion, {
      verificationId: record.id,
      updatedAt: FieldValue.serverTimestamp(),
      ...(completionStatus ? { status: completionStatus } : {}),
    });
    await batch.commit();
  }
}
