import type { Condition } from "./records";

/**
 * Permuted-block randomization (block size 4: two of each condition, shuffled). Keeps group
 * sizes within ±2 at any point, which matters for small thesis samples, while each individual
 * assignment stays unpredictable.
 */
export const ASSIGNMENT_METHOD = "server-permuted-block-4";

export interface AssignmentState {
  /** Remaining conditions in the current block. */
  block: Condition[];
  assignedManual: number;
  assignedAiAssisted: number;
}

export const initialAssignmentState = (): AssignmentState => ({ block: [], assignedManual: 0, assignedAiAssisted: 0 });

export function shuffledBlock(random: () => number): Condition[] {
  const block: Condition[] = ["manual", "manual", "aiAssisted", "aiAssisted"];
  for (let i = block.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [block[i], block[j]] = [block[j], block[i]];
  }
  return block;
}

/** Pure: next condition and the updated state. */
export function nextAssignment(state: AssignmentState, random: () => number): { condition: Condition; state: AssignmentState } {
  const block = state.block.length > 0 ? [...state.block] : shuffledBlock(random);
  const condition = block.shift() as Condition;
  return {
    condition,
    state: {
      block,
      assignedManual: state.assignedManual + (condition === "manual" ? 1 : 0),
      assignedAiAssisted: state.assignedAiAssisted + (condition === "aiAssisted" ? 1 : 0),
    },
  };
}
