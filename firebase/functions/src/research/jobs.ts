import { buildDailyRecords, type Condition, type DailyRecord, type RecordCompletion, type RecordTask } from "./records";
import { addDays, summarizeHistory, type ChallengeInput, type HabitInput } from "./resolver";

/** How much history is resolved (streaks need context) and how many recent days are rewritten. */
export const HISTORY_DAYS = 120;
export const REWRITE_DAYS = 14;

export interface Participant {
  uid: string;
  participantId: string;
  condition: Condition;
  timeZone: string;
  /** Research records are only produced for participants who consented. */
  consented: boolean;
}

export interface ParticipantData {
  habits: (HabitInput & { category?: string })[];
  completions: (RecordCompletion & CompletionLike)[];
  tasks: (RecordTask & { deadline: Date })[];
  challenges: ChallengeInput[];
  confidences: Map<string, number>;
}
type CompletionLike = { accountabilityTaskId?: string | null };

export interface ResearchStore {
  participants(): Promise<Participant[]>;
  load(uid: string, since: string): Promise<ParticipantData>;
  existingRecordDays(participantId: string, since: string): Promise<Set<string>>;
  writeRecords(records: DailyRecord[]): Promise<void>;
}

/** The participant's local calendar day at `now`. */
export function localDay(now: Date, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  } catch {
    return now.toISOString().slice(0, 10);
  }
}

/** Records to write: all recent (possibly still changing) days, plus any missing older days. */
export function selectRecordsToWrite(records: DailyRecord[], existing: Set<string>, today: string): DailyRecord[] {
  const rewriteFrom = addDays(today, -REWRITE_DAYS);
  return records.filter((r) => r.day >= rewriteFrom || !existing.has(r.day));
}

export async function refreshParticipant(store: ResearchStore, participant: Participant, now: Date): Promise<number> {
  if (!participant.consented) return 0;
  const today = localDay(now, participant.timeZone);
  const since = addDays(today, -HISTORY_DAYS);
  const data = await store.load(participant.uid, since);
  const summary = summarizeHistory(data.habits, data.completions, data.tasks, data.challenges, since, today, now);
  const records = buildDailyRecords(participant.participantId, participant.condition, summary, data.habits,
    data.completions, data.tasks, data.confidences, now);
  const existing = await store.existingRecordDays(participant.participantId, since);
  const toWrite = selectRecordsToWrite(records, existing, today);
  if (toWrite.length > 0) await store.writeRecords(toWrite);
  return toWrite.length;
}

export async function refreshAllParticipants(store: ResearchStore, now: Date): Promise<{ participants: number; records: number }> {
  let participants = 0;
  let records = 0;
  for (const participant of await store.participants()) {
    if (!participant.consented) continue;
    participants += 1;
    records += await refreshParticipant(store, participant, now);
  }
  return { participants, records };
}
