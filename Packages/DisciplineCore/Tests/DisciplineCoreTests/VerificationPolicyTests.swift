import XCTest
@testable import DisciplineCore

final class VerificationPolicyTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct Expected: Decodable {
                let status: String?
                let confidence: Double?
                let flagsInclude: String?
                let error: String?
            }
            let name: String
            let response: String
            let expected: Expected
        }
        let criteria: [VerificationCriterion]
        let threshold: Double
        let cases: [Case]
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/verification-policy-cases.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Runs the shared vectors that the TypeScript implementation also runs.
    func testSharedVectors() throws {
        let fixture = try loadFixture()
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 10)
        for testCase in fixture.cases {
            let outcome = Result {
                try VerificationPolicy.decide(
                    VerificationPolicy.parse(Data(testCase.response.utf8)),
                    criteria: fixture.criteria,
                    threshold: fixture.threshold
                )
            }
            switch (outcome, testCase.expected.error) {
            case (.success(let decision), nil):
                XCTAssertEqual(decision.status.rawValue, testCase.expected.status, testCase.name)
                XCTAssertEqual(decision.confidence, testCase.expected.confidence ?? -1, accuracy: 1e-9, testCase.name)
                XCTAssertEqual(decision.criteria.count, fixture.criteria.count, testCase.name)
                if let flag = testCase.expected.flagsInclude {
                    XCTAssertTrue(decision.flags.contains(flag), testCase.name)
                }
            case (.failure(let error), let expectedError?):
                XCTAssertEqual((error as? VerificationPolicyError)?.code, expectedError, testCase.name)
            case (.success(let decision), let expectedError?):
                XCTFail("\(testCase.name): expected \(expectedError), got \(decision.status)")
            case (.failure(let error), nil):
                XCTFail("\(testCase.name): unexpected error \(error)")
            }
        }
    }

    func testCompletionStatusMapping() {
        XCTAssertEqual(VerificationStatus.verified.completionStatus, .verified)
        XCTAssertEqual(VerificationStatus.rejected.completionStatus, .rejected)
        XCTAssertEqual(VerificationStatus.uncertain.completionStatus, .uncertain)
        XCTAssertNil(VerificationStatus.error.completionStatus, "pipeline errors keep the completion retryable")
    }

    func testBundledCatalogCoversEveryCategory() {
        let catalog = VerificationCriteriaCatalog.bundled
        XCTAssertEqual(catalog.version, "criteria-v1")
        XCTAssertEqual(catalog.defaultConfidenceThreshold, 0.7)
        for category in HabitCategory.allCases {
            let criteria = catalog.criteria(for: category)
            XCTAssertEqual(criteria.first?.id, "authentic_photo", "\(category) starts with the shared authenticity check")
            XCTAssertGreaterThanOrEqual(criteria.count, 2, "\(category)")
            XCTAssertEqual(Set(criteria.map(\.id)).count, criteria.count, "\(category) has duplicate criterion ids")
        }
        XCTAssertEqual(catalog.criteria(for: .gym).map(\.id),
                       ["authentic_photo", "workout_environment", "equipment_visible", "relevant_to_activity"])
    }
}
