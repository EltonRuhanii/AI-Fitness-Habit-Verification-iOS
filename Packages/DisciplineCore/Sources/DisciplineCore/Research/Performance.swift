import Foundation

/// Measurements for the thesis performance analysis, recorded on the device.
public enum PerformanceMetric: String, Codable, CaseIterable, Sendable {
    /// Photo upload plus the pending completion write (ms).
    case evidenceUpload
    /// Verification round trip: callable → AI model → policy → result (ms).
    case aiVerification
    /// Analysed camera frames per second during an exercise session (fps).
    case cameraFrameRate
    /// Mean on-device Vision analysis time per frame during a session (ms).
    case frameProcessing

    public var title: String {
        switch self {
        case .evidenceUpload: return "Evidence upload"
        case .aiVerification: return "AI verification"
        case .cameraFrameRate: return "Camera analysis rate"
        case .frameProcessing: return "Vision processing per frame"
        }
    }

    public var unit: String { self == .cameraFrameRate ? "fps" : "ms" }
}

public struct PerformanceSample: Codable, Equatable, Sendable {
    public let metric: PerformanceMetric
    public let value: Double
    public let recordedAt: Date
    /// Free-form context, e.g. the verification provider or the counting mode.
    public let context: String?

    public init(metric: PerformanceMetric, value: Double, recordedAt: Date = Date(), context: String? = nil) {
        self.metric = metric
        self.value = value
        self.recordedAt = recordedAt
        self.context = context
    }
}

public struct PerformanceStats: Equatable, Sendable {
    public let count: Int
    public let mean: Double
    public let median: Double
    /// Nearest-rank 95th percentile.
    public let p95: Double
    public let min: Double
    public let max: Double
}

public enum PerformanceSummary {
    public static func stats(_ values: [Double]) -> PerformanceStats? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        let median = n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
        let rank = Int((0.95 * Double(n)).rounded(.up))
        return PerformanceStats(count: n, mean: sorted.reduce(0, +) / Double(n), median: median,
                                p95: sorted[Swift.max(rank, 1) - 1], min: sorted[0], max: sorted[n - 1])
    }

    public static func summarize(_ samples: [PerformanceSample]) -> [PerformanceMetric: PerformanceStats] {
        Dictionary(grouping: samples, by: \.metric).compactMapValues { stats($0.map(\.value)) }
    }

    public static func csv(_ samples: [PerformanceSample]) -> String {
        let iso = ISO8601DateFormatter()
        let rows = samples.sorted { $0.recordedAt < $1.recordedAt }.map { sample in
            [sample.metric.rawValue, String(format: "%.2f", sample.value), sample.metric.unit,
             iso.string(from: sample.recordedAt), sample.context ?? ""]
        }
        return ResearchCSV.encode(header: ["metric", "value", "unit", "recorded_at", "context"], rows: rows)
    }
}

/// Accumulates camera frames during an exercise session.
public struct FrameRateMeter: Sendable {
    private var first: TimeInterval?
    private var last: TimeInterval?
    private var frames = 0
    private var processingTotal: TimeInterval = 0
    private var processedFrames = 0

    public init() {}

    public mutating func record(_ frame: PoseFrame) {
        if first == nil { first = frame.timestamp }
        last = frame.timestamp
        frames += 1
        if let processing = frame.processingDuration {
            processingTotal += processing
            processedFrames += 1
        }
    }

    /// Analysed frames per second; nil until at least a second of frames was seen.
    public var framesPerSecond: Double? {
        guard let first, let last, last - first >= 1, frames > 1 else { return nil }
        return Double(frames - 1) / (last - first)
    }

    public var meanProcessingMilliseconds: Double? {
        processedFrames > 0 ? processingTotal / Double(processedFrames) * 1000 : nil
    }
}
