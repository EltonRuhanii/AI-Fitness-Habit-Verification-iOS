import Foundation
import Observation
import DisciplineCore

/// On-device log of performance measurements (upload time, AI verification latency, camera
/// analysis rate) for the thesis performance analysis. Kept locally, exportable as CSV.
@MainActor
@Observable
final class PerformanceLog {
    static let capacity = 1000
    private static let key = "performance.samples"

    private(set) var samples: [PerformanceSample]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        samples = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PerformanceSample].self, from: $0) } ?? []
    }

    func record(_ metric: PerformanceMetric, _ value: Double, context: String? = nil) {
        guard value.isFinite, value >= 0 else { return }
        samples.append(PerformanceSample(metric: metric, value: value, context: context))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
        persist()
    }

    /// Runs `work` and records its duration in milliseconds (only when it succeeds).
    func measure<T>(_ metric: PerformanceMetric, context: String? = nil, _ work: () async throws -> T) async rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await work()
        let elapsed = start.duration(to: clock.now)
        record(metric, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15, context: context)
        return result
    }

    func clear() {
        samples = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(samples) { defaults.set(data, forKey: Self.key) }
    }
}
