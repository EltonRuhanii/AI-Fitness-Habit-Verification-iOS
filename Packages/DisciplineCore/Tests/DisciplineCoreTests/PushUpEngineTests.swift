import XCTest
@testable import DisciplineCore

/// Tests use synthetic side-view poses: a horizontal body with a controllable elbow angle
/// and hip sag, sampled at 15 fps.
final class PushUpEngineTests: XCTestCase {
    private var time: TimeInterval = 0

    /// Side-view push-up pose (left side) in normalized coordinates, aspect ratio 1.
    private func pose(elbow angle: Double, sag: Double = 0, confidence: Double = 0.9,
                      standing: Bool = false, scale: Double = 1, dropped: Set<Joint> = []) -> PoseFrame {
        time += 1.0 / 15
        var points: [Joint: (Double, Double)]
        if standing {
            points = [.leftShoulder: (0.5, 0.8), .leftElbow: (0.5, 0.65), .leftWrist: (0.5, 0.5),
                      .leftHip: (0.5, 0.5), .leftKnee: (0.5, 0.3), .leftAnkle: (0.5, 0.1)]
        } else {
            let shoulder = (0.3, 0.45)
            let elbow = (shoulder.0, shoulder.1 - 0.12 * scale)
            let radians = angle * .pi / 180
            let wrist = (elbow.0 + 0.12 * scale * sin(radians), elbow.1 + 0.12 * scale * cos(radians))
            points = [.leftShoulder: shoulder, .leftElbow: elbow, .leftWrist: wrist,
                      .leftHip: (0.3 + 0.25 * scale, 0.45 - sag), .leftKnee: (0.3 + 0.37 * scale, 0.45),
                      .leftAnkle: (0.3 + 0.5 * scale, 0.45)]
        }
        var landmarks: [Joint: Landmark] = [:]
        for (joint, p) in points where !dropped.contains(joint) {
            landmarks[joint] = Landmark(x: p.0, y: p.1, confidence: confidence)
        }
        return PoseFrame(timestamp: time, landmarks: landmarks, aspectRatio: 1)
    }

    private func calibratedEngine() -> PushUpEngine {
        var engine = PushUpEngine()
        for _ in 0..<12 { _ = engine.process(pose(elbow: 170)) }
        return engine
    }

    /// Feeds each angle for `hold` frames and returns every emitted repetition.
    private func run(_ engine: inout PushUpEngine, angles: [Double], hold: Int = 4, sag: Double = 0) -> [RepetitionOutcome] {
        var reps: [RepetitionOutcome] = []
        for angle in angles {
            for _ in 0..<hold {
                if let rep = engine.process(pose(elbow: angle, sag: sag)).repetition { reps.append(rep) }
            }
        }
        return reps
    }

    // MARK: Geometry

    func testAngleHelper() {
        XCTAssertEqual(Geometry.angle(Point2D(x: 0, y: 1), vertex: Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(Geometry.angle(Point2D(x: -1, y: 0), vertex: Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)), 180, accuracy: 1e-9)
    }

    func testAspectRatioCorrection() {
        // In normalized coordinates this is a right angle, but in a 1:2 portrait image the
        // actual pixel geometry is narrower (≈53°). Angles must use corrected coordinates.
        let frame = PoseFrame(timestamp: 0, landmarks: [
            .leftShoulder: Landmark(x: 0, y: 0, confidence: 1),
            .leftElbow: Landmark(x: 0.5, y: 0.5, confidence: 1),
            .leftWrist: Landmark(x: 1, y: 0, confidence: 1)
        ], aspectRatio: 0.5)
        let angle = Geometry.angle(frame.point(.leftShoulder, minConfidence: 0)!, vertex: frame.point(.leftElbow, minConfidence: 0)!,
                                   frame.point(.leftWrist, minConfidence: 0)!)
        XCTAssertEqual(angle, 53.13, accuracy: 0.01)
    }

    func testSyntheticPoseProducesRequestedElbowAngle() {
        var engine = PushUpEngine(configuration: { var c = PushUpConfiguration(); c.smoothing = 1; return c }())
        XCTAssertEqual(engine.process(pose(elbow: 123)).primaryAngle ?? 0, 123, accuracy: 0.001)
    }

    // MARK: Calibration

    func testDoesNotCountBeforeCalibration() {
        var engine = PushUpEngine()
        let first = engine.process(pose(elbow: 170))
        XCTAssertEqual(first.phase, .calibrating)
        XCTAssertEqual(first.feedback, .holdStill)
        XCTAssertTrue(run(&engine, angles: [80, 170], hold: 1).isEmpty, "reps during calibration are not counted")
    }

    func testCalibrationIssues() {
        var engine = PushUpEngine()
        XCTAssertEqual(engine.process(pose(elbow: 170, standing: true)).calibrationIssues, [.notInPosition])
        XCTAssertEqual(engine.process(pose(elbow: 170, dropped: [.leftAnkle])).calibrationIssues, [.bodyNotVisible])
        XCTAssertEqual(engine.process(pose(elbow: 170, dropped: [.leftAnkle])).feedback, .fullBodyNotVisible)
        XCTAssertTrue(engine.process(pose(elbow: 170, scale: 0.3)).calibrationIssues.contains(.moveCloser))
        XCTAssertTrue(engine.process(pose(elbow: 170, scale: 1.45)).calibrationIssues.contains(.moveFarther))
        XCTAssertEqual(engine.process(pose(elbow: 170, confidence: 0.4)).calibrationIssues, [.poorVisibility])
    }

    func testCalibrationCompletesAfterConsecutiveGoodFrames() {
        var engine = PushUpEngine()
        var last: ExerciseUpdate?
        for _ in 0..<10 { last = engine.process(pose(elbow: 170)) }
        XCTAssertEqual(last?.phase, .waitingForStart)
        XCTAssertEqual(engine.process(pose(elbow: 170)).phase, .up)
    }

    func testMustStartFromTopPosition() {
        var engine = PushUpEngine()
        for _ in 0..<12 { _ = engine.process(pose(elbow: 100)) }
        XCTAssertEqual(engine.process(pose(elbow: 100)).feedback, .startAtTop)
        XCTAssertTrue(run(&engine, angles: [80, 100], hold: 4).isEmpty)
    }

    // MARK: Repetitions

    func testValidRepetition() {
        var engine = calibratedEngine()
        let reps = run(&engine, angles: [170, 130, 85, 130, 170])
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.isValid, true)
        XCTAssertNil(reps.first?.fault)
        XCTAssertLessThanOrEqual(reps.first?.minimumAngle ?? 999, 95)
    }

    func testTenValidRepetitions() {
        var engine = calibratedEngine()
        let reps = run(&engine, angles: Array(repeating: [120, 85, 120, 170], count: 10).flatMap { $0 })
        XCTAssertEqual(reps.filter(\.isValid).count, 10)
        XCTAssertEqual(reps.count, 10)
    }

    func testPartialRepetitionIsInvalidInsufficientDepth() {
        var engine = calibratedEngine()
        let reps = run(&engine, angles: [170, 125, 110, 125, 170])
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.isValid, false)
        XCTAssertEqual(reps.first?.fault, .insufficientDepth)
    }

    func testSmallWobbleAtTopIsIgnored() {
        var engine = calibratedEngine()
        XCTAssertTrue(run(&engine, angles: [170, 138, 170, 136, 170]).isEmpty)
    }

    func testSaggingBodyIsInvalid() {
        var engine = calibratedEngine()
        // Hip sag of 0.08 bends the shoulder–hip–ankle line well below 150°.
        let reps = run(&engine, angles: [170, 85, 170], sag: 0.08)
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.fault, .bodyNotStraight)
    }

    func testBounceWithoutLockoutIsInvalidThenNextFullRepCounts() {
        var engine = calibratedEngine()
        let reps = run(&engine, angles: [170, 85, 125, 85, 170])
        XCTAssertEqual(reps.map(\.fault), [.incompleteLockout, nil])
        XCTAssertEqual(reps.map(\.isValid), [false, true])
    }

    func testNoiseAroundThresholdsDoesNotDoubleCount() {
        var engine = calibratedEngine()
        // Jittery bottom and top: samples oscillating a few degrees around the thresholds.
        let angles: [Double] = [170, 120, 90, 86, 91, 85, 90, 120, 148, 152, 147, 153, 170]
        let reps = run(&engine, angles: angles, hold: 1)
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.isValid, true)
    }

    // MARK: Tracking

    func testBriefDropoutKeepsRep() {
        var engine = calibratedEngine()
        var reps = run(&engine, angles: [170, 85])
        _ = engine.process(pose(elbow: 85, dropped: Set(Joint.allCases)))   // one lost frame (~67 ms)
        reps += run(&engine, angles: [170])
        XCTAssertEqual(reps.map(\.isValid), [true])
    }

    func testLongDropoutMidRepIsTrackingLostAndRecalibrates() {
        var engine = calibratedEngine()
        var reps = run(&engine, angles: [170, 85])
        var update: ExerciseUpdate?
        for _ in 0..<20 { // ~1.3 s without a body
            update = engine.process(pose(elbow: 85, dropped: Set(Joint.allCases)))
            if let rep = update?.repetition { reps.append(rep) }
        }
        XCTAssertEqual(reps.map(\.fault), [.trackingLost])
        XCTAssertEqual(update?.phase, .calibrating)
        XCTAssertTrue(run(&engine, angles: [170], hold: 2).isEmpty, "must recalibrate before counting again")
    }

    func testStandingUpMidRepAbortsIt() {
        var engine = calibratedEngine()
        var reps = run(&engine, angles: [170, 85])
        if let rep = engine.process(pose(elbow: 170, standing: true)).repetition { reps.append(rep) }
        XCTAssertEqual(reps.map(\.fault), [.trackingLost])
    }

    // MARK: Feedback

    func testFeedbackDuringDescent() {
        var engine = calibratedEngine()
        _ = run(&engine, angles: [170, 125], hold: 3)
        XCTAssertEqual(engine.process(pose(elbow: 125)).feedback, .goLower)
        _ = run(&engine, angles: [85], hold: 3)
        XCTAssertEqual(engine.process(pose(elbow: 110)).feedback, .returnToTop)
        XCTAssertEqual(engine.process(pose(elbow: 110, sag: 0.08)).feedback, .keepBodyStraight)
    }

    // MARK: Recorder

    func testRecorderCountsTowardRemainingTarget() {
        let task = AccountabilityTask(userId: "u", sourceHabitId: "h", sourceCompletionId: "c", day: DayKey(year: 2026, month: 9, day: 29),
                                      title: "10 Push-Ups", description: "", type: .pushUps, target: 10,
                                      deadline: Date().addingTimeInterval(3600))
        var recorder = ExerciseSessionRecorder(task: task, exercise: .pushUps, engineVersion: "pushup-v1", alreadyCompleted: 7)
        XCTAssertEqual(recorder.session.targetReps, 3)
        let valid = RepetitionOutcome(isValid: true, fault: nil, minimumAngle: 84.44, maximumAngle: 171.06)
        let invalid = RepetitionOutcome(isValid: false, fault: .insufficientDepth, minimumAngle: 110, maximumAngle: 170)
        recorder.record(valid)
        recorder.record(invalid)
        recorder.record(valid)
        XCTAssertFalse(recorder.isTargetReached)
        recorder.record(valid)
        XCTAssertTrue(recorder.isTargetReached)
        let session = recorder.finish()
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.validReps, 3)
        XCTAssertEqual(session.invalidReps, 1)
        XCTAssertEqual(session.repetitions.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(session.repetitions.first?.minimumAngle, 84.4)
        XCTAssertEqual(session.engineVersion, "pushup-v1")

        recorder.record(valid)
        XCTAssertEqual(recorder.session.validReps, 3, "no reps after finishing")
    }

    func testRecorderOutcomeWhenStoppedEarly() {
        let task = AccountabilityTask(userId: "u", sourceHabitId: "h", sourceCompletionId: "c", day: DayKey(year: 2026, month: 9, day: 29),
                                      title: "50 Push-Ups", description: "", type: .pushUps, target: 50,
                                      deadline: Date().addingTimeInterval(3600))
        var abandoned = ExerciseSessionRecorder(task: task, exercise: .pushUps, engineVersion: "v")
        XCTAssertEqual(abandoned.finish().outcome, .abandoned)
        var interrupted = ExerciseSessionRecorder(task: task, exercise: .pushUps, engineVersion: "v")
        XCTAssertEqual(interrupted.finish(interrupted: true).outcome, .interrupted)
    }
}
