import UIKit
import Observation
import DisciplineCore

/// Runs one camera exercise session for an accountability task:
/// permission → camera → calibration → counting → finish → store session.
@MainActor
@Observable
final class ExerciseSessionModel {
    /// How repetitions are observed. Face mode is the default: easiest setup.
    enum CountingMode: String, CaseIterable, Identifiable {
        /// Phone flat under the face; counts depth + lockout from face size.
        case face
        /// Phone ~2 m to the side; full body pose, also checks body straightness.
        case sideView

        var id: String { rawValue }

        var title: String {
            switch self {
            case .face: return "Face · easy"
            case .sideView: return "Side view · strict"
            }
        }
    }

    private static let modeKey = "exercise.countingMode"

    enum Stage: Equatable {
        case preparing
        case running
        case finished(ExerciseSession)
        case failed(String)
    }

    let task: AccountabilityTask
    let camera: PoseSource

    private(set) var stage: Stage = .preparing
    private(set) var update: ExerciseUpdate?
    private(set) var landmarks: [Joint: Landmark] = [:]
    private(set) var face: FaceBox?
    private(set) var mode: CountingMode
    private(set) var imageAspect: Double = 9.0 / 16.0
    private(set) var recorder: ExerciseSessionRecorder
    /// Increments on each valid / invalid rep; drives haptics and animations.
    private(set) var validEvents = 0
    private(set) var invalidEvents = 0
    private(set) var lastFault: RepetitionFault?

    private var engine: any ExerciseVerificationEngine
    private let store: HabitsStore
    private let repository: ExerciseSessionRepository
    private var frameTask: Task<Void, Never>?

    init(task: AccountabilityTask, store: HabitsStore, repository: ExerciseSessionRepository, source: PoseSource = PoseCamera()) {
        self.camera = source
        let mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(CountingMode.init(rawValue:)) ?? .face
        let engine = Self.makeEngine(for: mode)
        self.task = task
        self.store = store
        self.repository = repository
        self.mode = mode
        self.engine = engine
        self.recorder = Self.makeRecorder(task: task, engine: engine)
    }

    private static func makeEngine(for mode: CountingMode) -> any ExerciseVerificationEngine {
        switch mode {
        case .face: return FacePushUpEngine()
        case .sideView: return PushUpEngine()
        }
    }

    private static func makeRecorder(task: AccountabilityTask, engine: any ExerciseVerificationEngine) -> ExerciseSessionRecorder {
        ExerciseSessionRecorder(
            task: task,
            exercise: ExerciseKind(taskType: task.type) ?? .pushUps,
            engineVersion: engine.version,
            method: engine.method,
            alreadyCompleted: task.progress
        )
    }

    /// Switching is allowed until the first repetition is recorded; a session uses one method.
    var canChangeMode: Bool { recorder.session.repetitions.isEmpty }

    func setMode(_ newMode: CountingMode) {
        guard newMode != mode, canChangeMode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        engine = Self.makeEngine(for: newMode)
        recorder = Self.makeRecorder(task: task, engine: engine)
        camera.setMode(newMode == .face ? .face : .bodyPose)
        update = nil
        landmarks = [:]
        face = nil
    }

    var validReps: Int { recorder.session.validReps }
    var invalidReps: Int { recorder.session.invalidReps }
    var targetReps: Int { recorder.session.targetReps }

    func start() async {
        guard stage == .preparing else { return }
        if camera.requiresCameraPermission {
            switch await CameraPermission.request() {
            case .granted:
                break
            case .denied:
                stage = .failed("Camera access is turned off. Enable it in Settings to count your repetitions.")
                return
            case .unavailable:
                stage = .failed("This device has no camera available for counting repetitions.")
                return
            }
        }

        do {
            try camera.configure()
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        do {
            try store.markStarted(task)
        } catch {
            Log.data.error("Couldn't mark task started: \(error.localizedDescription, privacy: .public)")
        }

        UIApplication.shared.isIdleTimerDisabled = true
        camera.setMode(mode == .face ? .face : .bodyPose)
        camera.start()
        stage = .running
        frameTask = Task { [weak self, camera] in
            for await frame in camera.frames {
                self?.handle(frame)
            }
        }
    }

    private func handle(_ frame: PoseFrame) {
        guard stage == .running else { return }
        landmarks = frame.landmarks
        face = frame.face
        imageAspect = frame.aspectRatio
        let result = engine.process(frame)
        update = result
        if let repetition = result.repetition {
            recorder.record(repetition)
            if repetition.isValid {
                validEvents += 1
            } else {
                invalidEvents += 1
                lastFault = repetition.fault
            }
            if recorder.isTargetReached {
                finish(interrupted: false)
            }
        }
    }

    /// Ends the session (target reached, participant ended it, or the app was interrupted)
    /// and stores it. Idempotent.
    func finish(interrupted: Bool) {
        guard stage == .running || stage == .preparing else { return }
        frameTask?.cancel()
        camera.stop()
        camera.finishStream()
        UIApplication.shared.isIdleTimerDisabled = false

        let session = recorder.finish(interrupted: interrupted)
        // Sessions with no repetitions at all carry no information; don't store them.
        if session.validReps + session.invalidReps > 0 {
            do {
                try repository.save(session)
            } catch {
                stage = .failed(AppError.from(error).localizedDescription)
                return
            }
        }
        stage = .finished(session)
    }
}
