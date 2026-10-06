import Foundation

/// Body landmarks used by exercise engines (a subset of Apple Vision's body-pose joints).
public enum Joint: String, CaseIterable, Codable, Sendable {
    case nose
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

/// A detected landmark in normalized image coordinates (0…1, origin bottom-left, as in Vision).
public struct Landmark: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct Point2D: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A detected face in normalized image coordinates (origin bottom-left).
public struct FaceBox: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let confidence: Double

    public init(x: Double, y: Double, width: Double, height: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

/// One analysed camera frame. An empty `landmarks` dictionary means no body was detected;
/// `face` is only filled by face-based analysis.
public struct PoseFrame: Sendable {
    /// Seconds on a monotonic clock (e.g. the sample buffer's presentation time).
    public let timestamp: TimeInterval
    public let landmarks: [Joint: Landmark]
    /// Width / height of the (oriented) image. Normalized coordinates are scaled by this before
    /// measuring angles; otherwise angles in a portrait frame would be distorted.
    public let aspectRatio: Double
    /// Largest detected face, when face analysis is used.
    public let face: FaceBox?
    /// Time the on-device analysis of this frame took (performance measurements).
    public let processingDuration: TimeInterval?

    public init(timestamp: TimeInterval, landmarks: [Joint: Landmark], aspectRatio: Double, face: FaceBox? = nil,
                processingDuration: TimeInterval? = nil) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.aspectRatio = aspectRatio
        self.face = face
        self.processingDuration = processingDuration
    }

    /// The landmark in aspect-corrected space (x scaled by the aspect ratio, y unchanged), if
    /// detected with at least `minConfidence`.
    public func point(_ joint: Joint, minConfidence: Double) -> Point2D? {
        guard let landmark = landmarks[joint], landmark.confidence >= minConfidence else { return nil }
        return Point2D(x: landmark.x * aspectRatio, y: landmark.y)
    }
}

public enum Geometry {
    /// Angle at `vertex` between the rays to `a` and `c`, in degrees (0…180).
    public static func angle(_ a: Point2D, vertex b: Point2D, _ c: Point2D) -> Double {
        let v1 = (x: a.x - b.x, y: a.y - b.y)
        let v2 = (x: c.x - b.x, y: c.y - b.y)
        let lengths = (v1.x * v1.x + v1.y * v1.y).squareRoot() * (v2.x * v2.x + v2.y * v2.y).squareRoot()
        guard lengths > 0 else { return 0 }
        let cosine = max(-1, min(1, (v1.x * v2.x + v1.y * v2.y) / lengths))
        return acos(cosine) * 180 / .pi
    }

    public static func distance(_ a: Point2D, _ b: Point2D) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Angle of the line a→b from horizontal, in degrees (0 = horizontal, 90 = vertical).
    public static func tiltFromHorizontal(_ a: Point2D, _ b: Point2D) -> Double {
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        return atan2(dy, dx) * 180 / .pi
    }
}

// MARK: - Engine contract

/// Why the setup isn't usable yet. Counting doesn't start until there are none.
public enum CalibrationIssue: String, Codable, CaseIterable, Sendable {
    /// Required landmarks (shoulder, elbow, wrist, hip, ankle on one side) not detected.
    case bodyNotVisible
    /// Landmarks too close to the frame edge: the camera is too close.
    case moveFarther
    /// Body occupies too little of the frame for reliable measurement.
    case moveCloser
    /// Body isn't in the exercise's starting orientation (e.g. standing for push-ups).
    case notInPosition
    /// Landmarks detected with low confidence: usually poor lighting or occlusion.
    case poorVisibility
    /// Face-based counting: no face detected.
    case faceNotVisible
    /// Face-based counting: the top position wasn't held steadily enough to measure.
    case notStill
}

public enum FormFeedback: String, Codable, Sendable {
    case holdStill
    case startAtTop
    case good
    case goLower
    case returnToTop
    case keepBodyStraight
    case moveFarther
    case moveCloser
    case fullBodyNotVisible
    case getIntoPosition
    case poorVisibility
    case faceNotVisible
}

public enum MovementPhase: String, Codable, Sendable {
    case calibrating
    case waitingForStart
    case up
    case down
}

/// A finished repetition as judged by an engine.
public struct RepetitionOutcome: Equatable, Sendable {
    public let isValid: Bool
    public let fault: RepetitionFault?
    public let minimumValue: Double
    public let maximumValue: Double

    public init(isValid: Bool, fault: RepetitionFault?, minimumValue: Double, maximumValue: Double) {
        self.isValid = isValid
        self.fault = fault
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
    }
}

public struct ExerciseUpdate: Equatable, Sendable {
    public let phase: MovementPhase
    public let calibrationIssues: [CalibrationIssue]
    public let feedback: FormFeedback
    /// Set only on the frame where a repetition ends.
    public let repetition: RepetitionOutcome?
    /// The engine's primary joint angle this frame (smoothed), for display/debugging.
    public let primaryValue: Double?

    public var isCalibrated: Bool { phase != .calibrating }
}

/// An exercise-specific analyser: pose frames in, calibration + form + repetitions out.
///
/// Engines are pure value types with no camera or UI dependencies, so their thresholds and
/// state machines can be unit-tested with synthetic poses. Adding squats, sit-ups or lunges
/// means adding another conforming type.
public protocol ExerciseVerificationEngine: Sendable {
    var exercise: ExerciseKind { get }
    var method: ExerciseVerificationMethod { get }
    /// Identifies the thresholds/state machine; stored on every session for reproducibility.
    var version: String { get }
    mutating func reset()
    mutating func process(_ frame: PoseFrame) -> ExerciseUpdate
}
