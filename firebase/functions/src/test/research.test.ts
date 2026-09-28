import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { initialAssignmentState, nextAssignment, shuffledBlock, type AssignmentState } from "../research/assignment";
import { buildDailyRecords, DAILY_HEADER, dailyCsv, eventsCsv } from "../research/records";
import {
  addDays, DEFAULT_RULES, startOfWeek, summarizeHistory, weekday,
  type ChallengeInput, type CompletionInput, type HabitInput, type Rules, type TaskInput,
} from "../research/resolver";

// ---------- shared history vectors (same file as the Swift tests) ----------

interface Fixture {
  cases: {
    name: string;
    today: string;
    from: string;
    now: string;
    habits: HabitInput[];
    completions: CompletionInput[];
    tasks?: { id: string; status: TaskInput["status"]; deadline: string }[];
    challenges?: { id: string; startDate: string; durationDays: number; rules: Partial<Rules> }[];
    expected: { outcomes: string[]; current: number; longest: number };
  }[];
}

const fixture = JSON.parse(readFileSync(path.resolve(
  __dirname, "../../../../Packages/DisciplineCore/Tests/DisciplineCoreTests/Fixtures/history-resolution-cases.json",
), "utf8")) as Fixture;

test("calendar helpers match Swift semantics", () => {
  assert.equal(weekday("2026-09-27"), 1, "Sunday = 1");
  assert.equal(weekday("2026-09-28"), 2, "Monday = 2");
  assert.equal(startOfWeek("2026-09-27"), "2026-09-21");
  assert.equal(startOfWeek("2026-09-28"), "2026-09-28");
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
});

for (const c of fixture.cases) {
  test(`shared history vector: ${c.name}`, () => {
    const challenges: ChallengeInput[] = (c.challenges ?? []).map((ch) => ({
      id: ch.id,
      status: "active",
      startDate: ch.startDate,
      endDate: addDays(ch.startDate, ch.durationDays - 1),
      createdAt: new Date(0),
      rules: { ...DEFAULT_RULES, ...ch.rules },
    }));
    const tasks: TaskInput[] = (c.tasks ?? []).map((t) => ({ ...t, deadline: new Date(t.deadline) }));
    const summary = summarizeHistory(c.habits, c.completions, tasks, challenges, c.from, c.today, new Date(c.now));
    assert.deepEqual(summary.days.map((d) => d.resolution.outcome), c.expected.outcomes);
    assert.equal(summary.current, c.expected.current);
    assert.equal(summary.longest, c.expected.longest);
  });
}

// ---------- records + CSV ----------

test("daily records count events and verification confidence", () => {
  const habits: HabitInput[] = [{ id: "gym", frequency: "daily", unit: "sessions", targetCount: 1, startDate: "2026-09-28" }];
  const completions = [
    { habitId: "gym", day: "2026-09-28", status: "rejected" as const, method: "photoVerification", verificationId: "v1" },
    { habitId: "gym", day: "2026-09-28", status: "verified" as const, method: "photoVerification", verificationId: "v2" },
  ];
  const now = new Date("2026-09-29T12:00:00Z");
  const summary = summarizeHistory(habits, completions, [], [], "2026-09-28", "2026-09-29", now);
  const records = buildDailyRecords("P-X", "aiAssisted", summary, habits, completions, [], new Map([["v1", 0.9], ["v2", 0.8]]), now);
  assert.equal(records.length, 2);
  assert.equal(records[0].outcome, "successful");
  assert.equal(records[0].requiredHabits, 1);
  assert.equal(records[0].completedHabits, 1);
  assert.equal(records[0].verifiedHabits, 1);
  assert.equal(records[0].rejectedHabits, 1);
  assert.equal(records[0].verificationCount, 2);
  assert.ok(Math.abs(records[0].verificationConfidenceSum - 1.7) < 1e-9);
  assert.equal(records[1].outcome, "pending");

  const csv = dailyCsv(records);
  const lines = csv.trim().split("\n");
  assert.equal(lines[0], DAILY_HEADER.join(","));
  assert.ok(lines[1].startsWith("P-X,2026-09-28,aiAssisted,,1,1,0,1,1,0,0,0,0,0,2,0.8500,successful,1,0,1,day-resolver-v1"), lines[1]);
});

test("events CSV escapes fields and exports no names", () => {
  const now = new Date("2026-09-29T12:00:00Z");
  const csv = eventsCsv([{
    participantId: "P-X", condition: "manual", habitCategory: "gym", now, dayOutcome: "failed",
    completion: { habitId: "h,1", day: "2026-09-28", status: "accountabilityRequired", method: "accountabilityExercise" },
    task: { id: "t", day: "2026-09-28", sourceHabitId: "h,1", status: "pending", deadline: new Date("2026-09-29T00:00:00Z"), type: "pushUps", target: 50 },
  }]);
  const row = csv.trim().split("\n")[1];
  assert.equal(row, 'P-X,2026-09-28,manual,"h,1",gym,accountabilityRequired,accountabilityExercise,1,,,pushUps,50,expired,failed,0');
});

// ---------- assignment ----------

test("permuted blocks: each block has two of each condition", () => {
  let seed = 42;
  const random = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
  let state: AssignmentState = initialAssignmentState();
  const assigned: string[] = [];
  for (let i = 0; i < 40; i++) {
    const next = nextAssignment(state, random);
    assigned.push(next.condition);
    state = next.state;
    const diff = Math.abs(state.assignedManual - state.assignedAiAssisted);
    assert.ok(diff <= 2, `imbalance ${diff} after ${i + 1}`);
  }
  for (let b = 0; b < 40; b += 4) {
    const block = assigned.slice(b, b + 4);
    assert.equal(block.filter((c) => c === "manual").length, 2);
  }
  assert.equal(state.assignedManual, 20);
  assert.equal(new Set(assigned.slice(0, 8).join("")).size > 0, true);
  assert.deepEqual([...shuffledBlock(() => 0)].sort(), ["aiAssisted", "aiAssisted", "manual", "manual"]);
});

// ---------- refresh job ----------

import { localDay, refreshAllParticipants, selectRecordsToWrite, type ResearchStore } from "../research/jobs";

test("local day follows the participant's time zone", () => {
  const now = new Date("2026-09-28T23:30:00Z");
  assert.equal(localDay(now, "UTC"), "2026-09-28");
  assert.equal(localDay(now, "Europe/Berlin"), "2026-09-29");
  assert.equal(localDay(now, "Not/AZone"), "2026-09-28");
});

test("refresh writes recent and missing days, only for consenting participants", async () => {
  const written: string[] = [];
  const store: ResearchStore = {
    async participants() {
      return [
        { uid: "u1", participantId: "P-1", condition: "manual", timeZone: "UTC", consented: true },
        { uid: "u2", participantId: "P-2", condition: "aiAssisted", timeZone: "UTC", consented: false },
      ];
    },
    async load() {
      return {
        habits: [{ id: "h", frequency: "daily", unit: "sessions", targetCount: 1, startDate: "2026-08-01" }],
        completions: [], tasks: [], challenges: [], confidences: new Map(),
      };
    },
    async existingRecordDays() { return new Set(["2026-08-01", "2026-08-02"]); },
    async writeRecords(records) { written.push(...records.map((r) => `${r.participantId}_${r.day}`)); },
  };
  const result = await refreshAllParticipants(store, new Date("2026-09-28T12:00:00Z"));
  assert.equal(result.participants, 1);
  assert.ok(written.every((id) => id.startsWith("P-1_")), "no records for non-consenting participants");
  assert.ok(!written.includes("P-1_2026-08-01"), "existing old days aren't rewritten");
  assert.ok(written.includes("P-1_2026-08-03"), "missing old days are backfilled");
  assert.ok(written.includes("P-1_2026-09-28"), "recent days are rewritten");
});

test("selectRecordsToWrite keeps the rewrite window", () => {
  const rec = (day: string) => ({ day } as never);
  const chosen = selectRecordsToWrite([rec("2026-09-01"), rec("2026-09-20")], new Set(["2026-09-01", "2026-09-20"]), "2026-09-28");
  assert.deepEqual(chosen.map((r: { day: string }) => r.day), ["2026-09-20"]);
});
