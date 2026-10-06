import XCTest
@testable import DisciplineCore

final class UsabilityTests: XCTestCase {
    func testScoring() {
        XCTAssertEqual(SUSQuestionnaire.score([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]), 100)
        XCTAssertEqual(SUSQuestionnaire.score([1, 5, 1, 5, 1, 5, 1, 5, 1, 5]), 0)
        XCTAssertEqual(SUSQuestionnaire.score(Array(repeating: 3, count: 10)), 50)
        // Worked example: odd (4,4,4,5,4) → 3+3+3+4+3 = 16; even (2,1,2,1,2) → 3+4+3+4+3 = 17; 33 × 2.5.
        XCTAssertEqual(SUSQuestionnaire.score([4, 2, 4, 1, 4, 2, 5, 1, 4, 2]), 82.5)
    }

    func testIncompleteOrOutOfRangeAnswersHaveNoScore() {
        XCTAssertNil(SUSQuestionnaire.score([3, 3, 3]))
        XCTAssertNil(SUSQuestionnaire.score([3, 3, 3, 3, 3, 3, 3, 3, 3, 0]))
        XCTAssertNil(SUSQuestionnaire.score([3, 3, 3, 3, 3, 3, 3, 3, 3, 6]))
        XCTAssertNil(SUSResponse.make(participantId: "P-1", condition: .aiAssisted, responses: [], challengeDay: nil))
    }

    func testRatingBands() {
        XCTAssertEqual(SUSQuestionnaire.rating(for: 45), "Poor")
        XCTAssertEqual(SUSQuestionnaire.rating(for: 68), "Good")
        XCTAssertEqual(SUSQuestionnaire.rating(for: 82.5), "Excellent")
    }

    func testCSVRecomputesTheScore() throws {
        var response = try XCTUnwrap(SUSResponse.make(participantId: "P-ABC", condition: .aiAssisted,
                                                      responses: [4, 2, 4, 1, 4, 2, 5, 1, 4, 2], challengeDay: 30,
                                                      now: Date(timeIntervalSince1970: 0)))
        response.score = 12   // a tampered client score is ignored
        let csv = ResearchCSV.usability([response])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(lines[1]), "P-ABC,aiAssisted,sus-v1,1970-01-01T00:00:00Z,30,4,2,4,1,4,2,5,1,4,2,82.5")
    }
}
