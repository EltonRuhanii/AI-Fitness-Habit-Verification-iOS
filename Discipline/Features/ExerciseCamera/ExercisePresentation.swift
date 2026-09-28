import SwiftUI
import DisciplineCore

extension FormFeedback {
    var message: String {
        switch self {
        case .holdStill: return "Hold still…"
        case .startAtTop: return "Start at the top, arms straight"
        case .good: return "Good form"
        case .goLower: return "Go lower"
        case .returnToTop: return "Push all the way up"
        case .keepBodyStraight: return "Keep your body straight"
        case .moveFarther: return "Move farther from the camera"
        case .moveCloser: return "Move closer to the camera"
        case .fullBodyNotVisible: return "Make sure your full body is visible"
        case .getIntoPosition: return "Get into push-up position"
        case .poorVisibility: return "Improve the lighting or clear the view"
        case .faceNotVisible: return "Look at the screen so your face is visible"
        }
    }

    var symbolName: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .holdStill: return "hand.raised.fill"
        case .startAtTop, .returnToTop: return "arrow.up.circle.fill"
        case .goLower: return "arrow.down.circle.fill"
        case .keepBodyStraight: return "ruler.fill"
        case .moveFarther, .moveCloser: return "arrow.left.and.right.circle.fill"
        case .fullBodyNotVisible, .getIntoPosition: return "figure.cooldown"
        case .poorVisibility: return "sun.max.fill"
        case .faceNotVisible: return "face.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .good: return Theme.Palette.success
        case .holdStill, .startAtTop: return Theme.Palette.info
        default: return Theme.Palette.warning
        }
    }
}

extension RepetitionFault {
    var message: String {
        switch self {
        case .insufficientDepth: return "Not deep enough"
        case .incompleteLockout: return "Didn't push all the way up"
        case .bodyNotStraight: return "Body not straight"
        case .trackingLost: return "Lost tracking"
        }
    }
}

/// Outline of the detected face (face mode).
struct FaceOverlay: View {
    let face: FaceBox?
    let imageAspect: Double

    var body: some View {
        Canvas { context, size in
            guard let face else { return }
            let mapping = AspectFillMapping(imageAspect: imageAspect, viewSize: size)
            // Vision's origin is bottom-left, so the box's top edge is at y + height.
            let topLeft = mapping.point(x: face.x, y: face.y + face.height)
            let bottomRight = mapping.point(x: face.x + face.width, y: face.y)
            let rect = CGRect(x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                              width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
            context.stroke(Path(roundedRect: rect, cornerRadius: 18), with: .color(Theme.Palette.accent), lineWidth: 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Stick-figure overlay of the detected landmarks.
struct SkeletonOverlay: View {
    let landmarks: [Joint: Landmark]
    let imageAspect: Double
    var minConfidence = 0.3

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        Canvas { context, size in
            let mapping = AspectFillMapping(imageAspect: imageAspect, viewSize: size)
            func point(_ joint: Joint) -> CGPoint? {
                guard let landmark = landmarks[joint], landmark.confidence >= minConfidence else { return nil }
                return mapping.point(x: landmark.x, y: landmark.y)
            }
            var path = Path()
            for (a, b) in Self.bones {
                if let p1 = point(a), let p2 = point(b) {
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
            }
            context.stroke(path, with: .color(Theme.Palette.accent.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for joint in Joint.allCases {
                if let p = point(joint) {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
