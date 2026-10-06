# Security Review

**Scope:** Firestore and Storage security rules, Cloud Functions, iOS client data handling, and secrets.
**Date:** 2026-09-29 (Phase 12). **Method:** manual review of every rule and function against the threat model below. Each finding was fixed and covered by an automated test (rules emulator tests or function unit tests).

## Threat model

| Actor | Goal | Primary defences |
|---|---|---|
| **Participant** (authenticated, possibly running a modified app) | Inflate their own adherence: fake verification, dodge accountability, re-score history | Server-only outcome writes; rule-level invariants; server time for deadlines |
| **Other authenticated user** | Read or alter another participant's data or photos | Owner-scoped rules on every collection and Storage path |
| **Unauthenticated attacker** | Read data or photos, run up AI costs | Everything requires auth; callable functions check auth; per-user AI caps |
| **Researcher** | Needs aggregate data, must not see identities | Pseudonymous records only; claim-gated export; no access to private documents or photos |
| **Prompt injection via habit text** | Make the model pass all criteria | Habit text delimited and declared as data; structured-output schema; the verdict comes from a fixed policy, not the model |

## Findings (Phase 12)

| # | Severity | Finding | Fix | Test |
|---|---|---|---|---|
| 1 | High | The client set an accountability task's `deadline` without bounds, so a participant could give themselves unlimited time | Rule: `request.time < deadline ≤ request.time + 48 h` at creation (deadline can't be extended later, as before) | `accountability deadline is at most 48 hours away` |
| 2 | High | `exerciseSessions.validReps` was unbounded, so one forged write could complete any task | Rule: `validReps ≤ targetReps ≤ 150`, `invalidReps ≤ 500` | `exercise sessions cannot claim more valid reps than their target` |
| 3 | High (research integrity) | Habits could be edited mid-challenge; lowering a target re-scores past days as successful | Rule: commitment fields locked while the habit's challenge is active (editor shows them locked); archiving still allowed | `habits in an active challenge cannot have their commitment changed` |
| 4 | Low | Completions could reference another user's habit ID | Rule: habit must belong to the caller | `completions must reference the participant's own habit` |
| 5 | Medium (cost) | Unlimited new evidence meant unlimited paid AI calls | Server: at most 30 verifications per participant per 24 h (besides 3 per photo) | `participants have a daily cap on AI verifications` |
| 6 | Low | Challenge status could be reversed (abandoned → active) | Rule: only draft → any, active → completed/abandoned | `challenge lifecycle cannot be reversed` |

Found and fixed during earlier phases (all tested):
- **Evidence overwrite:** evidence photos could be overwritten because Storage treats overwrites as `create`. Fixed with `resource == null`.
- **Rejected profile updates:** full-document profile rewrites would have been rejected after server-side condition assignment. Fixed with field-level updates.
- **Date-field equality:** equality checks on date fields were brittle, because Swift `Date` round-trips can differ by a nanosecond. Replaced with ordering checks.
- **Task progress:** task progress could be set by the client. The field is now locked.

## Verified properties (with tests)

- A participant cannot mark their own evidence verified, rejected or uncertain, or set a task completed/expired, a completion resolved/failed, a daily record, or a verification result.
- In the AI-assisted condition, evidence-required habits cannot be self-reported.
- The experimental condition, participant ID and assignment metadata cannot be changed or faked by the client.
- Verification results and exercise sessions are append-only.
- Evidence photos are readable only by their owner (and the Admin SDK); JPEG only, < 8 MB, write-once.
- Research records are readable only by researchers (claim) and by the participant they belong to.
- The AI provider key is stored only in Secret Manager.

## Residual risks (accepted, documented)

1. **Forged exercise sessions** from a modified client, within the bounds above. Mitigation path: Firebase App Check with App Attest, and server-side plausibility checks on repetition timing (the per-rep timestamps are stored).
2. **Reused or borrowed evidence photos.** The authenticity criterion and `captureSource` reduce but don't prevent this. Mitigation path: perceptual-hash duplicate detection across a participant's submissions.
3. **Demo mode** has no security boundary by design. It never runs when Firebase is configured and is visibly labelled.
4. **Editing non-challenge habits** can change how recent days are re-scored. Research records older than 14 days are not rewritten, and during a challenge the commitment is locked.
