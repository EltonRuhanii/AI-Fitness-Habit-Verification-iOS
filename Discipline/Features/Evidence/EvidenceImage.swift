import UIKit

enum EvidenceImage {
    /// Long-edge limit: large enough for reliable visual assessment, small enough to upload quickly.
    static let maxDimension: CGFloat = 1568

    /// Downscales and re-encodes as JPEG. Re-encoding from pixels drops all EXIF metadata,
    /// including GPS location, so no location data leaves the device.
    static func prepareJPEG(from image: UIImage, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
