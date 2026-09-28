# Discipline

**AI-assisted fitness habit tracking, accountability and verification for iOS.**

Discipline is the practical implementation for a university thesis investigating:

> *Does AI-assisted evidence verification improve user adherence and accountability compared with conventional self-reported habit tracking?*

Participants commit to habits (e.g. gym 4×/week, reading 100 pages/week). Each day, every due commitment must be **completed** (self-reported or with verified evidence) or **explicitly skipped** and resolved through an agreed **accountability task** (e.g. 50 push-ups counted by on-device computer vision). Resolved days build a streak. The app records behavioral events so that the **manual** and **AI-assisted** conditions can be compared.

> ⚠️ Automated verification is an *assessment against defined criteria*, not proof. The app never claims otherwise.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for implementation status and architecture decisions.

---

## Repository layout

```text
Discipline.xcodeproj         Xcode 16 project (synchronized folders — no per-file entries)
Discipline/                  iOS app target
  App/                       Entry point, composition root (AppContainer)
  Core/                      Configuration, design system, Firebase bootstrap, utilities
  Services/                  Protocols + Firebase and demo implementations
  Features/                  One folder per feature (views + view models)
  Resources/                 Asset catalog
Packages/DisciplineCore/     Platform-independent domain logic + unit tests
firebase/                    Firestore/Storage security rules, indexes, (Phase 5+) Cloud Functions
docs/                        Roadmap and technical/thesis documentation
.github/workflows/ci.yml     Core tests on Linux, iOS build on macOS
```

## Requirements

- Xcode 16.2 or later, iOS 17 or later
- A Firebase project (optional, since the app runs in demo mode without one)

## Running the app

1. Open `Discipline.xcodeproj`. Xcode resolves the Firebase Swift package automatically.
2. Select the **Discipline** scheme and an iPhone simulator, then press Run.

Without `GoogleService-Info.plist`, the app starts in **demo mode**: local on-device services with a visible "DEMO MODE" badge. Nothing is sent to any server.

Launch arguments (Scheme → Run → Arguments):

| Argument | Effect |
|---|---|
| `-demoMode` | Force demo mode even when Firebase is configured |
| `-resetLocalState` | Wipe demo data and preferences on launch (used by UI tests) |
| `-seedDemoData` | Populate demo history (Phase 12) |

## Firebase setup

1. Create a Firebase project and add an iOS app with bundle ID `com.eltonruhani.discipline`.
2. Download `GoogleService-Info.plist` into `Discipline/Resources/`. It is **git-ignored**, so never commit it.
3. Enable **Authentication → Email/Password**.
4. Create a **Firestore** database and a **Storage** bucket.
5. Deploy rules and indexes:

   ```bash
   cd firebase
   npx firebase-tools deploy --only firestore:rules,firestore:indexes,storage
   ```

### AI photo verification setup

Evidence photos are assessed by the `verifyEvidence` Cloud Function. The provider API key is stored in Google Secret Manager and never reaches the app.

1. Upgrade the Firebase project to the **Blaze** plan (required for Cloud Functions and outbound network calls).
2. Store the Anthropic API key as a secret:

   ```bash
   cd firebase
   npx firebase-tools functions:secrets:set ANTHROPIC_API_KEY
   ```

3. Deploy the function:

   ```bash
   npx firebase-tools deploy --only functions
   ```

The model defaults to `claude-opus-5`. To use a different Claude model, set the `VERIFICATION_MODEL` parameter when deploying (Firebase prompts for it, or add it to `firebase/functions/.env`). Every result records the model that produced it.

#### How a photo is verified

```text
App: photo → downscale + strip EXIF/GPS → private Storage upload
     → evidence + pending completion (one batch) → call verifyEvidence
Function: ownership + attempt-limit checks → criteria for the habit's category
     → vision model answers each criterion (structured JSON) + confidence + reason
     → deterministic policy: confidence < threshold → uncertain;
       all required criteria pass → verified; otherwise rejected
     → immutable `verifications` record + evidence/completion status (one batch)
```

- **Criteria** live in one file, `Packages/DisciplineCore/Sources/DisciplineCore/Resources/verification-criteria.json`. The app shows them to the participant before submission, and the function build copies the same file.
- **The model never returns a verdict**, only per-criterion answers. The verdict comes from a fixed policy implemented in Swift and TypeScript, and both run the same shared test cases (`Tests/DisciplineCoreTests/Fixtures/verification-policy-cases.json`).
- **Failures are recorded, not hidden.** Timeouts, provider errors, refusals and malformed output produce a `verifications` record with `status: "error"` and an `errorCode`. The completion stays `pendingVerification` so the participant can retry, with at most 3 attempts per photo.
- **Refusal fallback.** If the provider's safety classifier declines, the request is retried server-side on Anthropic's recommended fallback model (`fallbacks: "default"`). The served model is recorded.
- **Demo mode** runs Apple's on-device image classifier through the same policy. It is labelled as a demo classifier and is not used for study data.

### Accountability (skipping)

Skipping a session habit shows its pre-agreed consequence (e.g. 50 push-ups) and deadline, and the skip is only recorded after the participant explicitly accepts. Skipping creates an `accountabilityTasks` document and turns that day's occurrence into `accountabilityRequired`.

- **Completed:** valid camera-counted repetitions (Phase 7) reach the target before the deadline. The task becomes `completed` and the occurrence `resolved`, which counts toward the target as a separate status from `selfReported`/`verified`.
- **Expired:** the deadline passes first. The `expireAccountabilityTasks` scheduled function (every 15 min) sets the task to `expired` and the occurrence to `failed`. Demo mode applies the same rule on device.
- Clients can only create a task or start it (`pending → inProgress`). Completion and expiry are server-only, enforced by the security rules.
- Consequences are capped per exercise type (push-ups: 100) and the deadline is capped at 48 h.

### Exercise verification (computer vision)

Accountability push-ups are counted on the device. No video is recorded or uploaded. There are two counting modes, and each session records which one it used (`verificationMethod`, `engineVersion`), so they can be compared in the analysis.

| Mode | Setup | Checks | Engine |
|---|---|---|---|
| **Face** (default) | Phone flat on the floor under the face, screen up | Depth and lockout, via the face growing to ≥ 1.6× and returning to ≤ 1.2× of its size at the top | `FacePushUpEngine` (`pushup-face-v1`, `VNDetectFaceRectanglesRequest`) |
| **Side view** (strict) | Phone upright ~2 m to the side | Depth, lockout and body straightness from joint angles | `PushUpEngine` (`pushup-v1`, `VNDetectHumanBodyPoseRequest`) |

Face mode was added after real-world testing showed the side view was hard to set up. It trades the body-alignment check for much easier use.

Side-view pipeline:

```text
Front camera (AVFoundation, 720p) → Apple Vision VNDetectHumanBodyPoseRequest (~15 fps)
  → PoseFrame (13 landmarks, confidence, aspect ratio)
  → PushUpEngine (DisciplineCore, pure Swift):
      calibration gate: required landmarks ≥ 0.3 confidence, not at frame edge,
                        body ≥ 25% of frame width, body within 40° of horizontal,
                        mean confidence ≥ 0.5, for 10 consecutive frames
      elbow angle (shoulder–elbow–wrist, aspect-corrected, EMA-smoothed)
      state machine: up (≥150°) → down (<140°) → bottom (≤95°) → up (≥150°) = 1 rep
      valid only if the bottom was reached and shoulder–hip–ankle stayed ≥150°
      faults: insufficientDepth, incompleteLockout, bodyNotStraight, trackingLost
  → ExerciseSessionRecorder → exerciseSessions/{id} (per-rep events with min/max angle)
  → onExerciseSessionCreated (Cloud Function): sums valid reps before the deadline, using
    the server receive time, and completes the task / resolves the skipped occurrence
```

- **Engine:** thresholds live in `PushUpConfiguration`, and every session stores `engineVersion` (`pushup-v1`) for reproducibility.
- **Extensible:** new exercises implement the `ExerciseVerificationEngine` protocol. Squats, sit-ups and lunges are planned.
- **Tested:** the state machine is unit-tested with synthetic poses covering valid, partial, bounce, sagging, noise and tracking-loss cases (`PushUpEngineTests`).
- **Anti-cheating:** the live camera, continuous tracking, the calibration gate and the per-rep criteria make simple cheating harder. The server ignores client clocks for deadlines. A modified app could still forge a session, as listed under limitations.

### Security model (summary)

- Users can read only documents whose `userId` is their own uid.
- Verification outcomes (`verified`, `rejected`, `uncertain`, `resolved`, `failed`) can be written **only by Cloud Functions**. A client cannot mark its own evidence as verified.
- In the AI-assisted condition, evidence-required habits cannot be self-reported (enforced in rules).
- The participant's experimental condition and participant ID are immutable.
- Verification results and exercise sessions are append-only.
- Evidence photos live under `evidence/{uid}/`. They are private and immutable, and nothing is publicly readable.
- Research records (`dailyRecords`) are server-written and readable only by researchers (custom claim `researcher: true`).

Full rules: [`firebase/firestore.rules`](firebase/firestore.rules), [`firebase/storage.rules`](firebase/storage.rules).

## Testing

```bash
# Domain logic (runs on macOS or Linux)
swift test --package-path Packages/DisciplineCore
```

Cloud Functions (verification pipeline, including AI failure cases):

```bash
cd firebase/functions && npm ci && npm test
```

Security rules (starts the Firebase emulators; requires Java):

```bash
cd firebase/tests && npm ci && npm test
```

On Windows, without Xcode:

```bash
docker run --rm -v "$PWD:/repo" -w /repo swift:6.1 swift test --package-path Packages/DisciplineCore
```

## Data model (Firestore)

| Collection | Key | Written by | Purpose |
|---|---|---|---|
| `users` | auth uid | client | Profile, pseudonymous `participantId`, `trackingCondition` |
| `habits` | uuid | client | Commitments and their verification requirements |
| `habitCompletions` | uuid | client + functions | One occurrence with a 10-state status, method and condition |
| `challenges` | uuid | client | Duration and rules (locked once active) |
| `evidence` | uuid | client | Photo metadata; image in Storage |
| `verifications` | uuid | functions | Immutable AI verification attempts |
| `accountabilityTasks` | uuid | client + functions | Consequences of skipping |
| `exerciseSessions` | uuid | client | Immutable camera sessions with per-rep events |
| `dailyRecords` | `{participantId}_{day}` | functions | Research snapshot per participant-day |

## Known limitations

- **On-device exercise counts are client-reported.** Pose estimation runs on the participant's phone, so a modified client could forge a session. Rules restrict *who* can write, not whether the reps really happened. App Check is planned as a mitigation. The thesis should treat this as a threat-to-validity.
- The experimental condition is currently assigned randomly on the client and then locked by rules. Phase 10 moves assignment to a Cloud Function using balanced block randomization.
- AI photo verification can only assess what is visible in an image. It cannot establish that the participant performed the activity, and it can't reliably detect a reused or borrowed photo. `captureSource` (camera vs. library) is recorded so this can be analysed.
- Model outputs are not perfectly deterministic. Each result stores the provider, served model, prompt/criteria version and threshold so results stay attributable. Temperature can't be fixed on current Claude models.
