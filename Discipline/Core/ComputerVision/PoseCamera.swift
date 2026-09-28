import AVFoundation
import Vision
import DisciplineCore

/// Vision (iOS 18 SDK) declares its own `Joint`; refer to ours unambiguously.
private typealias BodyJoint = DisciplineCore.Joint

/// Front-camera capture + on-device analysis: body pose (side-view mode) or face rectangles
/// (face mode). Frames are analysed on a background queue and delivered as `PoseFrame`s.
/// Nothing is recorded or uploaded; only landmarks / the face box leave this type.
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

    enum AnalysisMode: Sendable {
        case bodyPose
        case face
    }

    let session = AVCaptureSession()
    /// Latest frame only: if analysis falls behind, older frames are dropped rather than queued.
    let frames: AsyncStream<PoseFrame>

    private let continuation: AsyncStream<PoseFrame>.Continuation
    private let queue = DispatchQueue(label: "com.eltonruhani.discipline.pose", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    /// Accessed only on `queue`.
    private var mode: AnalysisMode = .face
    private var lastAnalysis: TimeInterval = 0
    /// ~15 analysed frames per second is plenty for push-up tempo and saves battery.
    private let minInterval: TimeInterval = 1.0 / 15

    private static let jointMap: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
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

    func setMode(_ mode: AnalysisMode) {
        queue.async { self.mode = mode }
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

        if mode == .face {
            continuation.yield(PoseFrame(timestamp: timestamp, landmarks: [:], aspectRatio: aspectRatio,
                                         face: detectFace(with: handler)))
            return
        }

        var landmarks: [BodyJoint: Landmark] = [:]
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

    /// The largest detected face (the participant's, closest to the phone).
    private func detectFace(with handler: VNImageRequestHandler) -> FaceBox? {
        guard (try? handler.perform([faceRequest])) != nil,
              let face = faceRequest.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height })
        else { return nil }
        let box = face.boundingBox
        return FaceBox(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height, confidence: Double(face.confidence))
    }
}
