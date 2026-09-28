// TypeScript mirror of DisciplineCore's DayResolver, HistoryResolver and StreakCalculator.
// Both implementations run Packages/DisciplineCore/Tests/DisciplineCoreTests/Fixtures/history-resolution-cases.json,
// so the research records written here use the same definition of a day as the app's streak.

export const RESOLVER_VERSION = "day-resolver-v1";

// ---------- calendar days (yyyy-MM-dd, time-zone free) ----------

const toUTC = (day: string) => {
  const [y, m, d] = day.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
};
const fromUTC = (ms: number) => new Date(ms).toISOString().slice(0, 10);
export const addDays = (day: string, n: number) => fromUTC(toUTC(day) + n * 86_400_000);
export const daysBetween = (a: string, b: string) => Math.round((toUTC(b) - toUTC(a)) / 86_400_000);
/** 1 = Sunday … 7 = Saturday (Swift `Calendar.Component.weekday`). */
export const weekday = (day: string) => new Date(toUTC(day)).getUTCDay() + 1;
/** Monday of the day's week. */
export const startOfWeek = (day: string) => addDays(day, -((new Date(toUTC(day)).getUTCDay() + 6) % 7));

// ---------- models (fields used by the resolver) ----------

export type CompletionStatus =
  | "pending" | "selfReported" | "pendingVerification" | "verified" | "rejected" | "uncertain"
  | "skipped" | "accountabilityRequired" | "resolved" | "failed";
export type TaskStatus = "pending" | "inProgress" | "completed" | "failed" | "expired";
export type DayOutcome = "successful" | "failed" | "pending" | "restDay";

export interface Rules {
  requireAllHabits: boolean;
  allowSkipping: boolean;
  missedDayBehavior: "breakStreak" | "pauseStreak";
  uncertainPolicy: "countsAsResolved" | "requiresResubmission";
}
export const DEFAULT_RULES: Rules = {
  requireAllHabits: true,
  allowSkipping: true,
  missedDayBehavior: "breakStreak",
  uncertainPolicy: "countsAsResolved",
};

export interface HabitInput {
  id: string;
  challengeId?: string | null;
  frequency: "daily" | "weekly" | "custom";
  unit: "sessions" | "pages" | "minutes";
  targetCount: number;
  scheduledWeekdays?: number[];
  startDate: string;
  endDate?: string | null;
  isRequired?: boolean;
  isActive?: boolean;
}
export interface CompletionInput {
  habitId: string;
  day: string;
  status: CompletionStatus;
  quantity?: number;
  accountabilityTaskId?: string | null;
}
export interface TaskInput {
  id: string;
  status: TaskStatus;
  deadline: Date;
}
export interface ChallengeInput {
  id: string;
  status?: string;
  startDate: string;
  endDate: string;
  createdAt?: Date;
  rules: Rules;
}

export interface DueCommitment {
  habitId: string;
  resolution: "resolved" | "pending" | "unresolved";
}
export interface DayResolution {
  day: string;
  outcome: DayOutcome;
  due: DueCommitment[];
  hasCommitments: boolean;
}
export interface StreakDay {
  resolution: DayResolution;
  challengeId: string | null;
  streakBefore: number;
  streakAfter: number;
}
export interface StreakSummary {
  current: number;
  longest: number;
  days: StreakDay[];
}

// ---------- counting ----------

function counts(status: CompletionStatus, rules: Rules): boolean {
  switch (status) {
    case "selfReported":
    case "verified":
      return true;
    case "uncertain":
      return rules.uncertainPolicy === "countsAsResolved";
    case "resolved":
      return rules.allowSkipping;
    default:
      return false;
  }
}

const isOpenTask = (task: TaskInput, now: Date) =>
  (task.status === "pending" || task.status === "inProgress") && !(now > task.deadline);

function isInEffectForHistory(habit: HabitInput, day: string): boolean {
  if (day < habit.startDate) return false;
  if (habit.endDate) return day <= habit.endDate;
  return habit.isActive !== false;
}

function neededToday(habit: HabitInput, day: string, completions: CompletionInput[], rules: Rules): number | null {
  switch (habit.frequency) {
    case "daily":
      return habit.targetCount;
    case "custom":
      return (habit.scheduledWeekdays ?? []).includes(weekday(day)) ? habit.targetCount : null;
    case "weekly": {
      const weekStart = startOfWeek(day);
      let weekEnd = addDays(weekStart, 6);
      if (habit.endDate && habit.endDate < weekEnd) weekEnd = habit.endDate;
      const achievedBefore = completions
        .filter((c) => c.habitId === habit.id && counts(c.status, rules) && c.day >= weekStart && c.day < day)
        .reduce((sum, c) => sum + (c.quantity ?? 1), 0);
      const remainingNeed = habit.targetCount - achievedBefore;
      if (remainingNeed <= 0) return null;
      if (habit.unit !== "sessions") return day === weekEnd ? remainingNeed : null;
      const daysLeft = daysBetween(day, weekEnd) + 1;
      return remainingNeed >= daysLeft ? 1 : null;
    }
  }
}

function isAwaitingOutcome(todays: CompletionInput[], tasks: TaskInput[], now: Date): boolean {
  return todays.some((c) => {
    if (c.status === "pendingVerification") return true;
    if (c.status === "accountabilityRequired") {
      const task = c.accountabilityTaskId ? tasks.find((t) => t.id === c.accountabilityTaskId) : undefined;
      return task ? isOpenTask(task, now) : true;
    }
    return false;
  });
}

export function resolveDay(
  day: string, habits: HabitInput[], completions: CompletionInput[], tasks: TaskInput[],
  rules: Rules, today: string, now: Date,
): DayResolution {
  const inEffect = habits.filter((h) => h.isRequired !== false && isInEffectForHistory(h, day));
  if (inEffect.length === 0) return { day, outcome: "restDay", due: [], hasCommitments: false };

  const due: DueCommitment[] = [];
  for (const habit of inEffect) {
    const needed = neededToday(habit, day, completions, rules);
    if (needed === null) continue;
    const todays = completions.filter((c) => c.habitId === habit.id && c.day === day);
    const achieved = todays.filter((c) => counts(c.status, rules)).reduce((s, c) => s + (c.quantity ?? 1), 0);
    let resolution: DueCommitment["resolution"];
    if (achieved >= needed) resolution = "resolved";
    else if (isAwaitingOutcome(todays, tasks, now) || day >= today) resolution = "pending";
    else resolution = "unresolved";
    due.push({ habitId: habit.id, resolution });
  }

  const unresolved = due.some((d) => d.resolution === "unresolved");
  const pending = due.some((d) => d.resolution === "pending");
  let outcome: DayOutcome;
  if (rules.requireAllHabits || due.length === 0) outcome = unresolved ? "failed" : pending ? "pending" : "successful";
  else if (due.some((d) => d.resolution === "resolved")) outcome = "successful";
  else outcome = pending ? "pending" : "failed";
  return { day, outcome, due, hasCommitments: true };
}

export function challengeCovering(day: string, challenges: ChallengeInput[]): ChallengeInput | null {
  const covering = challenges.filter((c) => c.status !== "draft" && c.startDate <= day && day <= c.endDate);
  if (covering.length === 0) return null;
  return covering.reduce((a, b) => ((b.createdAt?.getTime() ?? 0) > (a.createdAt?.getTime() ?? 0) ? b : a));
}

/** History from the first habit start (bounded by `from`) through `today`, with streaks. */
export function summarizeHistory(
  habits: HabitInput[], completions: CompletionInput[], tasks: TaskInput[], challenges: ChallengeInput[],
  from: string, today: string, now: Date,
): StreakSummary {
  if (habits.length === 0) return { current: 0, longest: 0, days: [] };
  const firstStart = habits.map((h) => h.startDate).reduce((a, b) => (b < a ? b : a));
  let day = firstStart > from ? firstStart : from;
  let current = 0;
  let longest = 0;
  const days: StreakDay[] = [];
  while (day <= today) {
    const challenge = challengeCovering(day, challenges);
    const scoped = challenge ? habits.filter((h) => h.challengeId === challenge.id) : habits;
    const rules = challenge?.rules ?? DEFAULT_RULES;
    const resolution = resolveDay(day, scoped, completions, tasks, rules, today, now);
    const before = current;
    if (resolution.outcome === "successful") current += 1;
    else if (resolution.outcome === "failed" && rules.missedDayBehavior === "breakStreak") current = 0;
    longest = Math.max(longest, current);
    days.push({ resolution, challengeId: challenge?.id ?? null, streakBefore: before, streakAfter: current });
    day = addDays(day, 1);
  }
  return { current, longest, days };
}
