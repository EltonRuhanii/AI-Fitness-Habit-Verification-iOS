import XCTest
@testable import DisciplineCore

final class PerformanceTests: XCTestCase {
    func testStats() throws {
        let stats = try XCTUnwrap(PerformanceSummary.stats([400, 100, 300, 200]))
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats.mean, 250)
        XCTAssertEqual(stats.median, 250)
        XCTAssertEqual(stats.p95, 400)
        XCTAssertEqual(stats.min, 100)
        XCTAssertEqual(stats.max, 400)

        let many = try XCTUnwrap(PerformanceSummary.stats((1...100).map(Double.init)))
        XCTAssertEqual(many.median, 50.5)
        XCTAssertEqual(many.p95, 95)
        XCTAssertNil(PerformanceSummary.stats([]))
    }

    func testSummaryGroupsByMetricAndCSV() {
        let t = Date(timeIntervalSince1970: 0)
        let samples = [
            PerformanceSample(metric: .aiVerification, value: 2000, recordedAt: t, context: "claude"),
            PerformanceSample(metric: .aiVerification, value: 4000, recordedAt: t.addingTimeInterval(1)),
            PerformanceSample(metric: .evidenceUpload, value: 800, recordedAt: t.addingTimeInterval(2))
        ]
        let summary = PerformanceSummary.summarize(samples)
        XCTAssertEqual(summary[.aiVerification]?.mean, 3000)
        XCTAssertEqual(summary[.evidenceUpload]?.count, 1)
        XCTAssertNil(summary[.cameraFrameRate])
        let lines = PerformanceSummary.csv(samples).split(separator: "\n")
        XCTAssertEqual(lines.first, "metric,value,unit,recorded_at,context")
        XCTAssertEqual(lines[1], "aiVerification,2000.00,ms,1970-01-01T00:00:00Z,claude")
    }

    func testFrameRateMeter() {
        var meter = FrameRateMeter()
        XCTAssertNil(meter.framesPerSecond)
        for index in 0...30 {   // 31 frames over 2 seconds
            meter.record(PoseFrame(timestamp: 10 + Double(index) / 15, landmarks: [:], aspectRatio: 1,
                                   processingDuration: 0.02))
        }
        XCTAssertEqual(meter.framesPerSecond ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(meter.meanProcessingMilliseconds ?? 0, 20, accuracy: 0.001)
    }
}
