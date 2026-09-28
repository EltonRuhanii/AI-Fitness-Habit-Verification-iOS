import XCTest
@testable import DisciplineCore

/// Synthetic face-size sequences at 15 fps. Face height 0.2 = top position.
final class FacePushUpEngineTests: XCTestCase {
    private var time: TimeInterval = 0

    private func frame(_ height: Double?, confidence: Double = 0.9) -> PoseFrame {
        time += 1.0 / 15
        let face = height.map { FaceBox(x: 0.4, y: 0.4, width: $0, height: $0, confidence: confidence) }
        return PoseFrame(timestamp: time, landmarks: [:], aspectRatio: 0.5625, face: face)
    }

    private func calibratedEngine() -> FacePushUpEngine {
        var engine = FacePushUpEngine()
        for _ in 0..<12 { _ = engine.process(frame(0.2)) }
        return engine
    }

    private func run(_ engine: inout FacePushUpEngine, heights: [Double], hold: Int = 3) -> [RepetitionOutcome] {
        var reps: [RepetitionOutcome] = []
        for height in heights {
            for _ in 0..<hold {
                if let rep = engine.process(frame(height)).repetition { reps.append(rep) }
            }
        }
        return reps
    }

    func testEngineIdentity() {
        let engine = FacePushUpEngine()
        XCTAssertEqual(engine.method, .visionFaceProximity)
        XCTAssertEqual(engine.version, "pushup-face-v1")
        XCTAssertEqual(ExerciseVerificationMethod.visionFaceProximity.metric, "face_size_ratio_to_top")
    }

    // MARK: Calibration

    func testCalibratesAfterSteadyTopPosition() {
        var engine = FacePushUpEngine()
        var last: ExerciseUpdate?
        for _ in 0..<11 { last = engine.process(frame(0.2)) }
        XCTAssertEqual(last?.phase, .calibrating)
        XCTAssertEqual(last?.feedback, .holdStill)
        let done = engine.process(frame(0.2))
        XCTAssertEqual(done.phase, .up)
        XCTAssertTrue(done.isCalibrated)
    }

    func testCalibrationIssues() {
        var engine = FacePushUpEngine()
        XCTAssertEqual(engine.process(frame(nil)).calibrationIssues, [.faceNotVisible])
        XCTAssertEqual(engine.process(frame(nil)).feedback, .faceNotVisible)
        XCTAssertEqual(engine.process(frame(0.03)).calibrationIssues, [.moveCloser])
        engine.reset()
        XCTAssertEqual(engine.process(frame(0.6)).calibrationIssues, [.moveFarther])
        engine.reset()
        _ = engine.process(frame(0.2))
        XCTAssertEqual(engine.process(frame(0.3)).calibrationIssues, [.notStill])
        engine.reset()
        XCTAssertEqual(engine.process(frame(0.2, confidence: 0.2)).calibrationIssues, [.faceNotVisible])
    }

    func testDoesNotCountBeforeCalibration() {
        var engine = FacePushUpEngine()
        XCTAssertTrue(run(&engine, heights: [0.2, 0.36, 0.2], hold: 2).isEmpty)
    }

    // MARK: Repetitions

    func testValidRepetition() {
        var engine = calibratedEngine()
        let reps = run(&engine, heights: [0.2, 0.3, 0.36, 0.3, 0.2])
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.isValid, true)
        XCTAssertGreaterThanOrEqual(reps.first?.maximumValue ?? 0, 1.6)
    }

    func testTenRepetitions() {
        var engine = calibratedEngine()
        let reps = run(&engine, heights: Array(repeating: [0.36, 0.2], count: 10).flatMap { $0 })
        XCTAssertEqual(reps.count, 10)
        XCTAssertTrue(reps.allSatisfy(\.isValid))
    }

    func testShallowRepIsInvalid() {
        var engine = calibratedEngine()
        let reps = run(&engine, heights: [0.2, 0.29, 0.2])
        XCTAssertEqual(reps.map(\.fault), [.insufficientDepth])
    }

    func testSmallWobbleIsIgnored() {
        var engine = calibratedEngine()
        XCTAssertTrue(run(&engine, heights: [0.2, 0.25, 0.2, 0.25, 0.2]).isEmpty)
    }

    func testBounceWithoutLockout() {
        var engine = calibratedEngine()
        let reps = run(&engine, heights: [0.2, 0.36, 0.27, 0.36, 0.2])
        XCTAssertEqual(reps.map(\.fault), [.incompleteLockout, nil])
    }

    // MARK: Tracking

    func testBriefFaceLossAtBottomKeepsRep() {
        var engine = calibratedEngine()
        var reps = run(&engine, heights: [0.36])
        for _ in 0..<5 { _ = engine.process(frame(nil)) } // ~0.33 s: face too close / occluded
        reps += run(&engine, heights: [0.2])
        XCTAssertEqual(reps.map(\.isValid), [true])
    }

    func testLongFaceLossMidRepIsTrackingLostButKeepsCalibration() {
        var engine = calibratedEngine()
        var reps = run(&engine, heights: [0.36])
        for _ in 0..<20 {
            if let rep = engine.process(frame(nil)).repetition { reps.append(rep) }
        }
        XCTAssertEqual(reps.map(\.fault), [.trackingLost])
        // The top-position measurement is kept, so the next rep counts without recalibrating.
        reps += run(&engine, heights: [0.2, 0.36, 0.2])
        XCTAssertEqual(reps.map(\.isValid), [false, true])
    }

    func testRecorderStoresMethod() {
        let task = AccountabilityTask(userId: "u", sourceHabitId: "h", sourceCompletionId: "c", day: DayKey(year: 2026, month: 9, day: 29),
                                      title: "5 Push-Ups", description: "", type: .pushUps, target: 5,
                                      deadline: Date().addingTimeInterval(3600))
        let recorder = ExerciseSessionRecorder(task: task, exercise: .pushUps, engineVersion: "pushup-face-v1", method: .visionFaceProximity)
        XCTAssertEqual(recorder.session.verificationMethod, .visionFaceProximity)
    }
}
