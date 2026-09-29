import AVFoundation
import DisciplineCore

/// Anything that produces pose/face frames for an exercise session.
protocol PoseSource: AnyObject, Sendable {
    var frames: AsyncStream<PoseFrame> { get }
    /// Live camera session for the preview, if this source uses the camera.
    var captureSession: AVCaptureSession? { get }
    var requiresCameraPermission: Bool { get }
    func configure() throws
    func setMode(_ mode: PoseCamera.AnalysisMode)
    func start()
    func stop()
    func finishStream()
}

extension PoseCamera: PoseSource {
    var captureSession: AVCaptureSession? { session }
    var requiresCameraPermission: Bool { true }
}

/// UI-test source: replays a face-mode push-up sequence (steady top position, then repeated
/// down/up) through the real engine, faster than real time but with realistic timestamps.
final class ScriptedPoseSource: PoseSource, @unchecked Sendable {
    let frames: AsyncStream<PoseFrame>
    private let continuation: AsyncStream<PoseFrame>.Continuation
    private var task: Task<Void, Never>?

    init() {
        let stream = AsyncStream.makeStream(of: PoseFrame.self, bufferingPolicy: .unbounded)
        frames = stream.stream
        continuation = stream.continuation
    }

    var captureSession: AVCaptureSession? { nil }
    var requiresCameraPermission: Bool { false }
    func configure() throws {}
    func setMode(_ mode: PoseCamera.AnalysisMode) {}

    func start() {
        task = Task.detached { [continuation] in
            var timestamp: TimeInterval = 0
            func emit(_ height: Double) async {
                timestamp += 1.0 / 15
                continuation.yield(PoseFrame(timestamp: timestamp, landmarks: [:], aspectRatio: 0.5625,
                                             face: FaceBox(x: 0.4, y: 0.4, width: height, height: height, confidence: 0.95)))
                try? await Task.sleep(for: .milliseconds(8))
            }
            for _ in 0..<15 { await emit(0.2) }             // hold the top position
            while !Task.isCancelled {                         // down/up until the session ends
                for _ in 0..<4 { await emit(0.36) }
                for _ in 0..<4 { await emit(0.2) }
            }
        }
    }

    func stop() {
        task?.cancel()
    }

    func finishStream() {
        continuation.finish()
    }
}
