import SwiftUI
import DisciplineCore

struct ExerciseCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: ExerciseSessionModel
    @State private var confirmsEnd = false

    init(task: AccountabilityTask, store: HabitsStore, container: AppContainer) {
        let source: PoseSource = container.configuration.isUITesting ? ScriptedPoseSource() : PoseCamera()
        _model = State(initialValue: ExerciseSessionModel(task: task, store: store, repository: container.exerciseSessions, source: source))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.stage {
            case .preparing:
                ProgressView().tint(.white)
            case .running:
                runningView
            case .finished(let session):
                ExerciseSummaryView(task: model.task, session: session) { dismiss() }
            case .failed(let message):
                failureView(message)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app ends counting: repetitions must be observed continuously.
            // (Only `.background`: the permission prompt makes the scene briefly `.inactive`.)
            if phase == .background, model.stage == .running { model.finish(interrupted: true) }
        }
        .onDisappear { model.finish(interrupted: true) }
        .sensoryFeedback(.increase, trigger: model.validEvents)
        .sensoryFeedback(.error, trigger: model.invalidEvents)
        .statusBarHidden()
    }

    // MARK: Running

    private var runningView: some View {
        ZStack {
            if let session = model.camera.captureSession {
                CameraPreview(session: session)
                    .ignoresSafeArea()
            }
            Group {
                if model.mode == .face {
                    FaceOverlay(face: model.face, imageAspect: model.imageAspect)
                } else {
                    SkeletonOverlay(landmarks: model.landmarks, imageAspect: model.imageAspect)
                }
            }
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if model.update?.isCalibrated == true {
                    counterPanel
                } else {
                    setupPanel
                }
            }
            .padding(Theme.Spacing.md)
        }
        .confirmationDialog("End this session?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { model.finish(interrupted: false) }
        } message: {
            Text("\(model.validReps) valid repetitions so far will be saved toward your task.")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if model.validReps + model.invalidReps > 0 { confirmsEnd = true } else { model.finish(interrupted: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("End session")
            Spacer()
            Text(model.task.type.displayName.uppercased())
                .font(Theme.Typography.headline)
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Get set up")
                .font(Theme.Typography.title2)
                .foregroundStyle(.white)
            if model.canChangeMode {
                Picker("Counting mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    ForEach(ExerciseSessionModel.CountingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exercise.mode")
            }
            if model.mode == .face {
                faceSetup
            } else {
                sideViewSetup
            }
            if let feedback = model.update?.feedback {
                feedbackPill(feedback)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var faceSetup: some View {
        let issues = Set(model.update?.calibrationIssues ?? [.faceNotVisible])
        Text("Lay your phone flat on the floor under your face, screen up. Get into the top position with straight arms, look at the screen and hold still for a second.")
            .font(Theme.Typography.callout)
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        checklistRow("Face visible", ok: !issues.contains(.faceNotVisible))
        checklistRow("Right distance", ok: !issues.contains(.faceNotVisible) && !issues.contains(.moveCloser) && !issues.contains(.moveFarther))
        checklistRow("Holding still at the top", ok: model.update != nil && issues.isEmpty)
    }

    @ViewBuilder
    private var sideViewSetup: some View {
        let issues = Set(model.update?.calibrationIssues ?? [.bodyNotVisible])
        Text("Place your phone upright on the floor, about 2 m to your side, so your whole body is visible from the side. Stricter: also checks that your body stays straight.")
            .font(Theme.Typography.callout)
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        checklistRow("Full body visible", ok: !issues.contains(.bodyNotVisible))
        checklistRow("Right distance", ok: !issues.contains(.moveFarther) && !issues.contains(.moveCloser) && !issues.contains(.bodyNotVisible))
        checklistRow("In push-up position", ok: !issues.contains(.notInPosition) && !issues.contains(.bodyNotVisible))
        checklistRow("Clear view and lighting", ok: !issues.contains(.poorVisibility) && !issues.contains(.bodyNotVisible))
    }

    private func checklistRow(_ title: String, ok: Bool) -> some View {
        Label {
            Text(title).foregroundStyle(.white)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Theme.Palette.success : .white.opacity(0.5))
        }
        .font(Theme.Typography.callout)
        .accessibilityLabel("\(title): \(ok ? "OK" : "not yet")")
    }

    private var counterPanel: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(model.task.type.displayName.uppercased())
                .font(Theme.Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(model.validReps)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.validReps)
                Text("/ \(model.targetReps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.validReps) of \(model.targetReps) valid repetitions")

            ProgressBar(fraction: Double(model.validReps) / Double(max(model.targetReps, 1)), tint: Theme.Palette.accent, height: 10)

            HStack {
                if let feedback = model.update?.feedback {
                    feedbackPill(feedback)
                }
                Spacer()
                if model.invalidReps > 0 {
                    Text("\(model.invalidReps) not counted")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if let fault = model.lastFault {
                Text("Last rep not counted: \(fault.message)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .id(model.invalidEvents)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func feedbackPill(_ feedback: FormFeedback) -> some View {
        Label(feedback.message, systemImage: feedback.symbolName)
            .font(Theme.Typography.callout.weight(.semibold))
            .foregroundStyle(feedback.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(feedback.tint.opacity(0.18), in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: feedback)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Failure

    private func failureView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.warning)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.secondary)
            Button("Close") { dismiss() }
                .buttonStyle(.primary)
        }
        .padding(Theme.Spacing.lg)
    }
}

/// End-of-session report. Wording states what the system detected, not what "happened".
struct ExerciseSummaryView: View {
    let task: AccountabilityTask
    let session: ExerciseSession
    let onDone: () -> Void

    private var reachedTarget: Bool { session.outcome == .completed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("ACCOUNTABILITY SESSION")
                        .font(Theme.Typography.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Label(reachedTarget ? "Completed" : "Not completed yet",
                          systemImage: reachedTarget ? "checkmark.seal.fill" : "hourglass")
                        .font(Theme.Typography.title)
                        .foregroundStyle(reachedTarget ? Theme.Palette.success : Theme.Palette.warning)
                    Text(reachedTarget
                         ? "Computer vision detected \(session.validReps) repetitions satisfying the configured movement criteria."
                         : "Computer vision detected \(session.validReps) of \(session.targetReps) repetitions satisfying the configured movement criteria. You can continue before the deadline.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    row("Task", task.title)
                    row("Started", session.startedAt.formatted(date: .omitted, time: .shortened))
                    row("Completed", session.completedAt?.formatted(date: .omitted, time: .shortened) ?? "–")
                    row("Target", "\(session.targetReps)")
                    row("Valid repetitions", "\(session.validReps)")
                    row("Invalid repetitions", "\(session.invalidReps)", last: true)
                }
                .card(padding: 0)

                if session.invalidReps > 0 {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        SectionEyebrow(title: "Not counted")
                        ForEach(faultCounts) { entry in
                            HStack {
                                Text(entry.fault.message)
                                Spacer()
                                Text("\(entry.count)").monospacedDigit()
                            }
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        }
                    }
                    .card()
                }

                Text("\(methodDescription) (\(session.engineVersion)). No video was recorded or uploaded. Automated counting can make mistakes.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(.primary)
                .padding(Theme.Spacing.md)
                .accessibilityIdentifier("exercise.done")
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private struct FaultCount: Identifiable {
        let fault: RepetitionFault
        let count: Int
        var id: RepetitionFault { fault }
    }

    private var methodDescription: String {
        switch session.verificationMethod {
        case .visionBodyPose2D:
            return "Counted on this device from your body pose (side view): depth, lockout and body alignment"
        case .visionFaceProximity:
            return "Counted on this device from your face's distance to the phone: depth and lockout (body alignment isn't checked in this mode)"
        }
    }

    private var faultCounts: [FaultCount] {
        let faults = session.repetitions.compactMap(\.fault)
        return Dictionary(grouping: faults, by: { $0 })
            .map { FaultCount(fault: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private func row(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(value).foregroundStyle(Theme.Palette.textPrimary).monospacedDigit()
            }
            .font(Theme.Typography.callout)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            if !last { Divider().overlay(Theme.Palette.hairline) }
        }
    }
}
