import Foundation

/// Configurable movement criteria for push-ups. Angles in degrees.
public struct PushUpConfiguration: Equatable, Sendable {
    /// Elbow angle at or above which the arms count as extended (top of the rep).
    public var topAngle: Double = 150
    /// Elbow angle at or below which the rep is deep enough.
    public var bottomAngle: Double = 95
    /// Elbow angle below which a descent is considered started (hysteresis under `topAngle`).
    public var descentStartAngle: Double = 140
    /// A descent that never goes below this is treated as noise, not as an attempted rep.
    public var meaningfulDipAngle: Double = 130
    /// After reaching the bottom, rising above this and going down again without lockout is a fault.
    public var reboundAngle: Double = 120
    /// Minimum shoulder–hip–ankle angle for a straight body (180 = perfectly straight).
    public var minBodyLineAngle: Double = 150
    /// Maximum tilt of the shoulder→ankle line from horizontal to count as push-up position.
    public var maxBodyTilt: Double = 40
    /// Landmarks below this confidence are treated as not detected.
    public var minLandmarkConfidence: Double = 0.3
    /// Mean confidence of the used landmarks below this triggers "poor visibility".
    public var minMeanConfidence: Double = 0.5
    /// Shoulder–ankle length as a fraction of the frame width; below this the person is too far.
    public var minBodySpan: Double = 0.25
    /// Landmarks closer than this (normalized) to any edge mean the camera is too close.
    public var edgeMargin: Double = 0.02
    /// Consecutive good frames required before counting starts.
    public var calibrationFrames: Int = 10
    /// Weight of the newest sample in the exponential moving average of the elbow angle.
    public var smoothing: Double = 0.5
    /// Seconds without usable landmarks before the rep in progress is discarded.
    public var maxTrackingGap: TimeInterval = 1.0

    public init() {}
}

/// Side-view push-up repetition counter (strict mode: full body visible from the side).
///
/// State machine (elbow angle, smoothed):
///
///     calibrating ──(setup OK for N frames)──▶ waitingForStart ──(≥ top)──▶ up
///     up ──(< descentStart)──▶ down
///     down ──(≥ top)──▶ up          + rep: valid if it reached ≤ bottom with a straight body
///     down ──(bottom → rebound → bottom again, no lockout)──▶ down   + invalid rep (incomplete lockout)
///
/// Losing tracking or leaving position mid-rep records an invalid rep (tracking lost) and
/// returns to calibration.
public struct PushUpEngine: ExerciseVerificationEngine {
    public let exercise: ExerciseKind = .pushUps
    public let method: ExerciseVerificationMethod = .visionBodyPose2D
    public let version = "pushup-v1"
    public let configuration: PushUpConfiguration

    private enum Stage: Equatable {
        case calibrating(goodFrames: Int)
        case waitingForStart
        case up
        case down(Rep)
    }

    private struct Rep: Equatable {
        var minAngle: Double
        var maxAngle: Double
        var reachedBottom: Bool
        var rebounded: Bool
        var minBodyLine: Double
    }

    private struct Metrics {
        let elbowAngle: Double
        let bodyLineAngle: Double
        let issues: [CalibrationIssue]
    }

    private var stage: Stage = .calibrating(goodFrames: 0)
    private var smoothedElbow: Double?
    private var lastUsableTimestamp: TimeInterval?

    public init(configuration: PushUpConfiguration = PushUpConfiguration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        stage = .calibrating(goodFrames: 0)
        smoothedElbow = nil
        lastUsableTimestamp = nil
    }

    public mutating func process(_ frame: PoseFrame) -> ExerciseUpdate {
        guard let metrics = measure(frame) else {
            return handleMissingBody(at: frame.timestamp)
        }
        lastUsableTimestamp = frame.timestamp

        let smoothing = configuration.smoothing
        let elbow = smoothedElbow.map { smoothing * metrics.elbowAngle + (1 - smoothing) * $0 } ?? metrics.elbowAngle
        smoothedElbow = elbow

        // Setup problems: calibrate, or abort a rep in progress.
        if !metrics.issues.isEmpty {
            var aborted: RepetitionOutcome?
            if case .down(let rep) = stage {
                aborted = RepetitionOutcome(isValid: false, fault: .trackingLost, minimumValue: rep.minAngle, maximumValue: rep.maxAngle)
            }
            stage = .calibrating(goodFrames: 0)
            return update(.calibrating, issues: metrics.issues, feedback: feedback(for: metrics.issues), repetition: aborted, angle: elbow)
        }

        switch stage {
        case .calibrating(let goodFrames):
            let count = goodFrames + 1
            if count >= configuration.calibrationFrames {
                stage = .waitingForStart
                return update(.waitingForStart, feedback: .startAtTop, angle: elbow)
            }
            stage = .calibrating(goodFrames: count)
            return update(.calibrating, feedback: .holdStill, angle: elbow)

        case .waitingForStart:
            if elbow >= configuration.topAngle {
                stage = .up
                return update(.up, feedback: .good, angle: elbow)
            }
            return update(.waitingForStart, feedback: .startAtTop, angle: elbow)

        case .up:
            if elbow < configuration.descentStartAngle {
                stage = .down(Rep(minAngle: elbow, maxAngle: elbow, reachedBottom: elbow <= configuration.bottomAngle,
                                  rebounded: false, minBodyLine: metrics.bodyLineAngle))
                return update(.down, feedback: bodyFeedback(metrics) ?? .good, angle: elbow)
            }
            return update(.up, feedback: bodyFeedback(metrics) ?? .good, angle: elbow)

        case .down(var rep):
            rep.minAngle = min(rep.minAngle, elbow)
            rep.maxAngle = max(rep.maxAngle, elbow)
            rep.minBodyLine = min(rep.minBodyLine, metrics.bodyLineAngle)
            if elbow <= configuration.bottomAngle { rep.reachedBottom = true }

            // Back at the top: judge the repetition.
            if elbow >= configuration.topAngle {
                stage = .up
                if rep.minAngle > configuration.meaningfulDipAngle {
                    return update(.up, feedback: .good, angle: elbow) // a wobble, not an attempt
                }
                let fault: RepetitionFault? = !rep.reachedBottom ? .insufficientDepth
                    : (rep.minBodyLine < configuration.minBodyLineAngle ? .bodyNotStraight : nil)
                let outcome = RepetitionOutcome(isValid: fault == nil, fault: fault,
                                                minimumValue: rep.minAngle, maximumValue: max(rep.maxAngle, elbow))
                return update(.up, feedback: fault.map(Self.feedback(for:)) ?? .good, repetition: outcome, angle: elbow)
            }

            // Bounced partway up and went back down without locking out.
            if rep.reachedBottom && elbow >= configuration.reboundAngle { rep.rebounded = true }
            if rep.rebounded && elbow <= configuration.bottomAngle {
                let outcome = RepetitionOutcome(isValid: false, fault: .incompleteLockout,
                                                minimumValue: rep.minAngle, maximumValue: rep.maxAngle)
                stage = .down(Rep(minAngle: elbow, maxAngle: elbow, reachedBottom: true, rebounded: false,
                                  minBodyLine: metrics.bodyLineAngle))
                return update(.down, feedback: .returnToTop, repetition: outcome, angle: elbow)
            }

            stage = .down(rep)
            let formFeedback: FormFeedback = bodyFeedback(metrics) ?? (rep.reachedBottom ? .returnToTop : .goLower)
            return update(.down, feedback: formFeedback, angle: elbow)
        }
    }

    // MARK: Measurement

    private func measure(_ frame: PoseFrame) -> Metrics? {
        let c = configuration.minLandmarkConfidence
        typealias Side = (shoulder: Joint, elbow: Joint, wrist: Joint, hip: Joint, ankle: Joint)
        let sides: [Side] = [
            (.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle),
            (.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle)
        ]
        // Filmed from the side, one side of the body is clearer; use the more confident one.
        let usable = sides.compactMap { side -> (Side, Double)? in
            let joints = [side.shoulder, side.elbow, side.wrist, side.hip, side.ankle]
            let confidences = joints.compactMap { frame.landmarks[$0]?.confidence }
            guard confidences.count == joints.count, confidences.allSatisfy({ $0 >= c }) else { return nil }
            return (side, confidences.reduce(0, +) / Double(confidences.count))
        }
        guard let best = usable.max(by: { $0.1 < $1.1 }) else { return nil }
        let (side, meanConfidence) = best
        guard let shoulder = frame.point(side.shoulder, minConfidence: c),
              let elbow = frame.point(side.elbow, minConfidence: c),
              let wrist = frame.point(side.wrist, minConfidence: c),
              let hip = frame.point(side.hip, minConfidence: c),
              let ankle = frame.point(side.ankle, minConfidence: c)
        else { return nil }

        var issues: [CalibrationIssue] = []
        let normalized = [side.shoulder, side.elbow, side.wrist, side.hip, side.ankle].compactMap { frame.landmarks[$0] }
        let margin = configuration.edgeMargin
        if normalized.contains(where: { $0.x < margin || $0.x > 1 - margin || $0.y < margin || $0.y > 1 - margin }) {
            issues.append(.moveFarther)
        }
        let frameWidth = max(frame.aspectRatio, 0.0001)
        if Geometry.distance(shoulder, ankle) / frameWidth < configuration.minBodySpan {
            issues.append(.moveCloser)
        }
        if Geometry.tiltFromHorizontal(shoulder, ankle) > configuration.maxBodyTilt {
            issues.append(.notInPosition)
        }
        if meanConfidence < configuration.minMeanConfidence {
            issues.append(.poorVisibility)
        }

        return Metrics(
            elbowAngle: Geometry.angle(shoulder, vertex: elbow, wrist),
            bodyLineAngle: Geometry.angle(shoulder, vertex: hip, ankle),
            issues: issues
        )
    }

    private mutating func handleMissingBody(at timestamp: TimeInterval) -> ExerciseUpdate {
        let gap = lastUsableTimestamp.map { timestamp - $0 } ?? .infinity
        var aborted: RepetitionOutcome?
        if gap > configuration.maxTrackingGap {
            if case .down(let rep) = stage {
                aborted = RepetitionOutcome(isValid: false, fault: .trackingLost, minimumValue: rep.minAngle, maximumValue: rep.maxAngle)
            }
            stage = .calibrating(goodFrames: 0)
            smoothedElbow = nil
        }
        // Brief dropouts keep the current stage so a single missed frame doesn't break a rep.
        let phase: MovementPhase
        switch stage {
        case .calibrating: phase = .calibrating
        case .waitingForStart: phase = .waitingForStart
        case .up: phase = .up
        case .down: phase = .down
        }
        return update(phase, issues: [.bodyNotVisible], feedback: .fullBodyNotVisible, repetition: aborted, angle: smoothedElbow)
    }

    // MARK: Feedback

    private func bodyFeedback(_ metrics: Metrics) -> FormFeedback? {
        metrics.bodyLineAngle < configuration.minBodyLineAngle ? .keepBodyStraight : nil
    }

    private func feedback(for issues: [CalibrationIssue]) -> FormFeedback {
        // Most fundamental problem first.
        if issues.contains(.bodyNotVisible) { return .fullBodyNotVisible }
        if issues.contains(.moveFarther) { return .moveFarther }
        if issues.contains(.moveCloser) { return .moveCloser }
        if issues.contains(.poorVisibility) { return .poorVisibility }
        return .getIntoPosition
    }

    private static func feedback(for fault: RepetitionFault) -> FormFeedback {
        switch fault {
        case .insufficientDepth: return .goLower
        case .incompleteLockout: return .returnToTop
        case .bodyNotStraight: return .keepBodyStraight
        case .trackingLost: return .fullBodyNotVisible
        }
    }

    private func update(_ phase: MovementPhase, issues: [CalibrationIssue] = [], feedback: FormFeedback,
                        repetition: RepetitionOutcome? = nil, angle: Double?) -> ExerciseUpdate {
        ExerciseUpdate(phase: phase, calibrationIssues: issues, feedback: feedback, repetition: repetition, primaryValue: angle)
    }
}
