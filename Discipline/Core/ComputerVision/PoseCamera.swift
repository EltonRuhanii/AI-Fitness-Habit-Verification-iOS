import AVFoundation
import Vision
import DisciplineCore

/// Front-camera capture + on-device body-pose detection.
///
/// Frames are analysed with `VNDetectHumanBodyPoseRequest` on a background queue and delivered
/// as `PoseFrame`s. Nothing is recorded or uploaded; only landmarks leave this type.
final class PoseCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case unavailable
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "No front camera is available on this device."
            case .configurationFailed: return "The camera couldn't be started. Close other apps using the camera and try again."
            }
        }
    }

    let session = AVCaptureSession()
    /// Latest frame only: if analysis falls behind, older frames are dropped rather than queued.
    let frames: AsyncStream<PoseFrame>

    private let continuation: AsyncStream<PoseFrame>.Continuation
    private let queue = DispatchQueue(label: "com.eltonruhani.discipline.pose", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private var lastAnalysis: TimeInterval = 0
    /// ~15 analysed frames per second is plenty for push-up tempo and saves battery.
    private let minInterval: TimeInterval = 1.0 / 15

    private static let jointMap: [(VNHumanBodyPoseObservation.JointName, Joint)] = [
        (.nose, .nose),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
    ]

    override init() {
        let stream = AsyncStream.makeStream(of: PoseFrame.self, bufferingPolicy: .bufferingNewest(1))
        frames = stream.stream
        continuation = stream.continuation
        super.init()
    }

    func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.unavailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.configurationFailed }
        session.addOutput(output)
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func finishStream() {
        continuation.finish()
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp - lastAnalysis >= minInterval, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = timestamp

        // Buffers arrive in landscape sensor orientation. `.leftMirrored` makes Vision analyse the
        // upright, mirrored portrait image the user sees in the front-camera preview.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        // Oriented (portrait) image: width = buffer height, height = buffer width.
        let aspectRatio = Double(CVPixelBufferGetHeight(pixelBuffer)) / Double(max(CVPixelBufferGetWidth(pixelBuffer), 1))

        var landmarks: [Joint: Landmark] = [:]
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                let points = try observation.recognizedPoints(.all)
                for (visionJoint, joint) in Self.jointMap {
                    if let point = points[visionJoint], point.confidence > 0 {
                        landmarks[joint] = Landmark(x: point.location.x, y: point.location.y, confidence: Double(point.confidence))
                    }
                }
            }
        } catch {
            // A failed analysis is reported as "no body" for this frame; the engine handles gaps.
        }
        continuation.yield(PoseFrame(timestamp: timestamp, landmarks: landmarks, aspectRatio: aspectRatio))
    }
}
