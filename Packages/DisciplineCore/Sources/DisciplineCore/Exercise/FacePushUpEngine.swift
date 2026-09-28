import Foundation

/// Movement criteria for face-based push-ups. Ratios are face height relative to the
/// face height measured in the top position (1.0 = top; 2.0 = face appears twice as large).
public struct FacePushUpConfiguration: Equatable, Sendable {
    /// Ratio at or above which the rep is deep enough (face ≈ 40% closer than at the top).
    public var downRatio: Double = 1.6
    /// Ratio at or below which the participant is back at the top.
    public var upRatio: Double = 1.2
    /// Ratio above which a descent is considered started (hysteresis above `upRatio`).
    public var descentStartRatio: Double = 1.25
    /// A descent that never exceeds this is treated as noise, not an attempted rep.
    public var meaningfulDipRatio: Double = 1.35
    /// After reaching the bottom, dropping to this and going back down without reaching the
    /// top is an incomplete lockout.
    public var reboundRatio: Double = 1.4
    /// Face height (fraction of frame) below which the face is too far or too small to track.
    public var minFaceHeight: Double = 0.06
    /// Face height at the top above which the phone is too close to measure a descent.
    public var maxTopFaceHeight: Double = 0.45
    public var minFaceConfidence: Double = 0.5
    /// Consecutive steady frames needed to measure the top position.
    public var calibrationFrames: Int = 12
    /// Each calibration frame must be within this fraction of the running average.
    public var stabilityTolerance: Double = 0.12
    public var smoothing: Double = 0.5
    /// While at the top, the reference slowly follows small posture drift.
    public var baselineAdaptation: Double = 0.05
    public var maxTrackingGap: TimeInterval = 1.0

    public init() {}
}

/// Face-based push-up counter ("easy mode").
///
/// The phone lies flat on the floor under the participant's face, screen up. Going down
/// brings the face closer to the front camera, so it appears larger. The engine first
/// measures the face size in the top position, then counts a rep when the face grows to
/// `downRatio` × that size and shrinks back to `upRatio`.
///
/// Verifies depth and lockout. Unlike the side-view engine it cannot check body
/// straightness; sessions record `visionFaceProximity` so this difference is visible in data.
public struct FacePushUpEngine: ExerciseVerificationEngine {
    public let exercise: ExerciseKind = .pushUps
    public let method: ExerciseVerificationMethod = .visionFaceProximity
    public let version = "pushup-face-v1"
    public let configuration: FacePushUpConfiguration

    private enum Stage: Equatable {
        case calibrating(samples: [Double])
        case up
        case down(Rep)
    }

    private struct Rep: Equatable {
        var minRatio: Double
        var maxRatio: Double
        var reachedBottom: Bool
        var rebounded: Bool
    }

    private var stage: Stage = .calibrating(samples: [])
    private var baseline: Double?
    private var smoothedHeight: Double?
    private var lastSeen: TimeInterval?

    public init(configuration: FacePushUpConfiguration = FacePushUpConfiguration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        stage = .calibrating(samples: [])
        baseline = nil
        smoothedHeight = nil
        lastSeen = nil
    }

    public mutating func process(_ frame: PoseFrame) -> ExerciseUpdate {
        guard let face = frame.face, face.confidence >= configuration.minFaceConfidence, face.height > 0 else {
            return handleMissingFace(at: frame.timestamp)
        }
        lastSeen = frame.timestamp
        let height = smoothedHeight.map { configuration.smoothing * face.height + (1 - configuration.smoothing) * $0 } ?? face.height
        smoothedHeight = height

        switch stage {
        case .calibrating(var samples):
            return calibrate(height: height, samples: &samples)

        case .up:
            guard let baseline else { return restartCalibration(height: height) }
            let ratio = height / baseline
            if ratio >= configuration.descentStartRatio {
                stage = .down(Rep(minRatio: ratio, maxRatio: ratio, reachedBottom: ratio >= configuration.downRatio, rebounded: false))
                return update(.down, feedback: .goLower, value: ratio)
            }
            // Follow slow posture drift while resting at the top.
            if abs(ratio - 1) < 0.15 {
                self.baseline = baseline + configuration.baselineAdaptation * (height - baseline)
            }
            return update(.up, feedback: .good, value: ratio)

        case .down(var rep):
            guard let baseline else { return restartCalibration(height: height) }
            let ratio = height / baseline
            rep.minRatio = min(rep.minRatio, ratio)
            rep.maxRatio = max(rep.maxRatio, ratio)
            if ratio >= configuration.downRatio { rep.reachedBottom = true }

            if ratio <= configuration.upRatio {
                stage = .up
                if rep.maxRatio < configuration.meaningfulDipRatio {
                    return update(.up, feedback: .good, value: ratio) // a wobble, not an attempt
                }
                let fault: RepetitionFault? = rep.reachedBottom ? nil : .insufficientDepth
                let outcome = RepetitionOutcome(isValid: fault == nil, fault: fault,
                                                minimumValue: min(rep.minRatio, ratio), maximumValue: rep.maxRatio)
                return update(.up, feedback: fault == nil ? .good : .goLower, repetition: outcome, value: ratio)
            }

            if rep.reachedBottom && ratio <= configuration.reboundRatio { rep.rebounded = true }
            if rep.rebounded && ratio >= configuration.downRatio {
                let outcome = RepetitionOutcome(isValid: false, fault: .incompleteLockout,
                                                minimumValue: rep.minRatio, maximumValue: rep.maxRatio)
                stage = .down(Rep(minRatio: ratio, maxRatio: ratio, reachedBottom: true, rebounded: false))
                return update(.down, feedback: .returnToTop, repetition: outcome, value: ratio)
            }

            stage = .down(rep)
            return update(.down, feedback: rep.reachedBottom ? .returnToTop : .goLower, value: ratio)
        }
    }

    // MARK: Calibration

    private mutating func calibrate(height: Double, samples: inout [Double]) -> ExerciseUpdate {
        if height < configuration.minFaceHeight {
            stage = .calibrating(samples: [])
            return update(.calibrating, issues: [.moveCloser], feedback: .moveCloser, value: nil)
        }
        if height > configuration.maxTopFaceHeight {
            stage = .calibrating(samples: [])
            return update(.calibrating, issues: [.moveFarther], feedback: .moveFarther, value: nil)
        }
        let mean = samples.isEmpty ? height : samples.reduce(0, +) / Double(samples.count)
        if abs(height - mean) > configuration.stabilityTolerance * mean {
            stage = .calibrating(samples: [height])
            return update(.calibrating, issues: [.notStill], feedback: .holdStill, value: nil)
        }
        samples.append(height)
        if samples.count >= configuration.calibrationFrames {
            baseline = samples.reduce(0, +) / Double(samples.count)
            stage = .up
            return update(.up, feedback: .good, value: 1)
        }
        stage = .calibrating(samples: samples)
        return update(.calibrating, feedback: .holdStill, value: nil)
    }

    private mutating func restartCalibration(height: Double) -> ExerciseUpdate {
        var samples: [Double] = []
        return calibrate(height: height, samples: &samples)
    }

    private mutating func handleMissingFace(at timestamp: TimeInterval) -> ExerciseUpdate {
        let gap = lastSeen.map { timestamp - $0 } ?? .infinity
        var aborted: RepetitionOutcome?
        if gap > configuration.maxTrackingGap {
            if case .down(let rep) = stage {
                aborted = RepetitionOutcome(isValid: false, fault: .trackingLost, minimumValue: rep.minRatio, maximumValue: rep.maxRatio)
            }
            if case .calibrating = stage {} else {
                // Keep the measured top position; only a rep in progress is abandoned.
                stage = baseline == nil ? .calibrating(samples: []) : .up
            }
            smoothedHeight = nil
        }
        let phase: MovementPhase
        switch stage {
        case .calibrating: phase = .calibrating
        case .up: phase = .up
        case .down: phase = .down
        }
        return update(phase, issues: [.faceNotVisible], feedback: .faceNotVisible, repetition: aborted, value: nil)
    }

    private func update(_ phase: MovementPhase, issues: [CalibrationIssue] = [], feedback: FormFeedback,
                        repetition: RepetitionOutcome? = nil, value: Double?) -> ExerciseUpdate {
        ExerciseUpdate(phase: phase, calibrationIssues: issues, feedback: feedback, repetition: repetition, primaryValue: value)
    }
}
