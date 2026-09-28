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
| Experimental condition | Between-subjects, `manual` vs `aiAssisted`, immutable per participant | Stored on the profile and copied onto every completion and daily record. |

## Phases

| # | Phase | Status | Contents |
|---|---|---|---|
| 1 | Foundation | ✅ | Project, `DisciplineCore` models + tests, design system, DI container, Firebase bootstrap, auth (register/login/logout/reset/persistent), onboarding + rules consent, tab navigation, profile with sign-out and account deletion, Firestore and Storage security rules, CI |
| 2 | Habits | ✅ | Habit/completion repositories (Firestore + demo, local-first with sync monitor), create/edit/archive, self-report completion flow, daily/weekly/custom targets and monthly adherence in core + tests, idempotent completion IDs, starter template |
| 3 | Dashboard | 🔨 | ✅ Today's commitments, weekly goal bars, sync status · ⏳ streak display (Phase 8), accountability items (Phase 6), recent activity |
| 4 | Photo evidence | ✅ | Camera (permission handling) + PhotosPicker, preview/retake, downscale + EXIF/GPS stripping, private Storage upload, atomic evidence + pending completion |
| 5 | AI verification | ✅ | `verifyEvidence` Cloud Function (Claude, structured output, refusal fallback, secret key), shared criteria catalog, deterministic policy in Swift + TS with shared test vectors, immutable history incl. failures, retry, result UI, on-device demo verifier |
| 6 | Accountability | ✅ | Skip → consequence preview → explicit accept (nothing recorded on "Go back"), per-habit push-up consequence (10–100), task lifecycle in core + server, scheduled server-side expiry, dashboard accountability section with countdown |
| 7 | Exercise CV | ⏳ | Camera pipeline, Vision body pose, calibration, `ExerciseVerificationEngine` protocol, push-up state machine (core + tests), live UI, session storage |
| 8 | Streak engine | ⏳ | Day resolver (feasibility rule for weekly targets), streak calculation, calendar, milestones |
| 9 | Challenges | ⏳ | Challenge builder, rules configuration, 75-day template, rule locking |
| 10 | Research | ⏳ | Server-side condition assignment, `dailyRecords` writer, researcher dashboard, anonymous CSV export |
| 11 | Polish | ⏳ | Notifications, offline/sync indicators, animations, accessibility, performance |
| 12 | Testing & docs | ⏳ | UI tests (demo mode), rules unit tests (emulator), AI failure tests, thesis technical documentation |

## Verification approach

Development happens on Windows, so there is no local Xcode:

- **`DisciplineCore`** is built and tested locally with the official Swift Linux toolchain (Docker `swift:6.1`) and in CI.
- **App target:** every Swift file is syntax-checked locally with `swiftc -parse`. The full iOS build runs in GitHub Actions (`macos-15`) and in Xcode on a Mac.
