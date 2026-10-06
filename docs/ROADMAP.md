# Implementation Roadmap

Status legend: ✅ done · 🔨 in progress · ⏳ planned

## Starting point (2026-09-28)

The repository contained no Xcode project. `Discipline` had been committed as a broken
submodule pointer (git mode `160000`, no `.gitmodules`), so no source files were ever pushed.
The project was established from scratch.

## Architecture decisions

| Decision | Choice | Why |
|---|---|---|
| UI | SwiftUI, iOS 17+ | `@Observable`, `@Bindable`, and modern navigation make the code simpler. iOS 17 covers ~all active devices. |
| Pattern | MVVM + service protocols + composition root (`AppContainer`) | Every service (auth, repositories, AI, CV) has a Firebase and a demo implementation behind a protocol. |
| Domain logic | Separate Swift package `DisciplineCore` (Foundation only) | Streak, day resolution, AI-response policy, rep state machines and research export are pure and unit-testable on any platform, including CI on Linux. |
| Backend | Firebase Auth, Firestore, Storage, Cloud Functions (SPM, v12) | As specified. Firestore's persistent cache provides offline support. |
| AI photo verification | Cloud Function `verifyEvidence` → vision LLM, strict JSON schema | API keys stay server-side. The provider sits behind an interface on both the client and the server. |
| Exercise verification | Apple Vision `VNDetectHumanBodyPoseRequest`, on device | No video leaves the device. Deterministic, versioned thresholds. |
| Project file | Xcode 16 synchronized folders | Files added under `Discipline/` are picked up automatically, so no merge conflicts in the project file. |
| Demo mode | Auto-enabled when `GoogleService-Info.plist` is absent, or with `-demoMode` | The app runs and UI tests run without Firebase. A visible badge prevents confusion with study data. |
| Experimental condition | Server-assigned and immutable per participant; currently `ai-only` (everyone `aiAssisted`), two-arm permuted-block design switchable on the server | Stored on the profile and copied onto every completion and daily record. |

## Phases

| # | Phase | Status | Contents |
|---|---|---|---|
| 1 | Foundation | ✅ | Project, `DisciplineCore` models + tests, design system, DI container, Firebase bootstrap, auth (register/login/logout/reset/persistent), onboarding + rules consent, tab navigation, profile with sign-out and account deletion, Firestore and Storage security rules, CI |
| 2 | Habits | ✅ | Habit/completion repositories (Firestore + demo, local-first with sync monitor), create/edit/archive, self-report completion flow, daily/weekly/custom targets and monthly adherence in core + tests, idempotent completion IDs, starter template |
| 3 | Dashboard | ✅ | Today's commitments, weekly goals, sync status, accountability section, streak chip |
| 4 | Photo evidence | ✅ | Camera (permission handling) + PhotosPicker, preview/retake, downscale + EXIF/GPS stripping, private Storage upload, atomic evidence + pending completion |
| 5 | AI verification | ✅ | `verifyEvidence` Cloud Function (Claude, structured output, refusal fallback, secret key), shared criteria catalog, deterministic policy in Swift + TS with shared test vectors, immutable history incl. failures, retry, result UI, on-device demo verifier |
| 6 | Accountability | ✅ | Skip → consequence preview → explicit accept (nothing recorded on "Go back"), per-habit push-up consequence (10–100), task lifecycle in core + server, scheduled server-side expiry, dashboard accountability section with countdown |
| 7 | Exercise CV | ✅ | Front camera + Vision body pose, calibration gate, `ExerciseVerificationEngine` protocol, push-up state machine with faults (core + synthetic-pose tests), live counter UI with skeleton/feedback, session summary, `onExerciseSessionCreated` server resolution using server receive time |
| 8 | Streak engine | ✅ | DayResolver (feasibility rule for weekly targets, pending handling for verification/accountability, requireAllHabits), StreakCalculator (break/pause), milestones, streak page with 6-week calendar and per-day explanation, dashboard streak chip, history-preserving archive |
| 9 | Challenges | ✅ | 75 Day Discipline template + custom challenges (adopt existing habits), participant rules (streak, require-all, skipping + consequence, missed-day, uncertain policy), locked study parameters, explicit acceptance, rule lock, challenge-scoped streak/rules, day X of Y + adherence, auto-complete, abandon |
| 10 | Research | ✅ | Server permuted-block condition assignment, shared HistoryResolver (Swift + TS, shared vectors), nightly consent-gated daily records in participant time zone, researcher-claim dashboard (condition comparison), anonymous daily + events CSV export, account-deletion cleanup incl. research records |
| 11 | Polish | ✅ | Local notifications (planner in core + tests: evening reminder, accountability deadline, streak warning, weekly summary; quiet hours, 3/day cap, per-type toggles, contextual permission), offline banner with pending-change count, evidence offline guard, Settings (notifications, appearance, privacy & AI explanations, delete evidence photos, account), profile statistics |
| 12 | Testing & docs | ✅ | Security review (6 findings fixed, tested) and SECURITY_REVIEW.md; Progress screen (spec §34) with core calculator; deterministic demo history; XCUITest target with both spec flows in CI; TECHNICAL_DOCUMENTATION.md for the thesis |
| 13 | Challenge mode | ✅ | App runs only as a 90-day challenge: routine setup (workouts, runs, two daily 60-min skills, extras), strict daily rule, skill skips cover the missing minutes; free habits/editor/custom challenges removed from the UI; everyone AI-assisted (`ai-only` design, switchable); skill evidence criteria (`criteria-v2`) |
| 14 | Demo, widget, evaluation | ✅ | "Discipline Demo" scheme (auto sign-in, day-46 demo challenge); medium home-screen widget (streak + first three unfinished activities, midnight rollover); SUS usability questionnaire with server-side scoring in the export; on-device performance measurements with CSV export |

## Verification approach

Development happens on Windows, so there is no local Xcode:

- **`DisciplineCore`** is built and tested locally with the official Swift Linux toolchain (Docker `swift:6.1`) and in CI.
- **App target:** every Swift file is syntax-checked locally with `swiftc -parse`. The full iOS build runs in GitHub Actions (`macos-15`) and in Xcode on a Mac.
