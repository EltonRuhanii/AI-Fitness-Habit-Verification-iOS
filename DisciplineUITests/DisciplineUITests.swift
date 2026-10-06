import XCTest

/// End-to-end flows from the specification (§55), run in demo mode with deterministic stand-ins
/// for hardware: a generated sample photo, a stub verifier (all criteria pass, decided by the
/// real policy) and a scripted push-up sequence played through the real face engine.
final class DisciplineUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoMode", "-resetLocalState", "-forceCondition", "aiAssisted"]
        app.launch()
    }

    // MARK: Flow 1: Login → 90-day setup → Complete skill → Submit evidence → AI result → Progress

    func testEvidenceVerificationFlow() {
        registerAndOnboard()
        setUpChallenge()

        tap(app.buttons["commitment.action.Guitar"])
        tap(app.buttons["evidence.sample"])
        tap(app.buttons["evidence.submit"])
        XCTAssertTrue(element(labelContaining: "Evidence verified").waitForExistence(timeout: 15), "AI result shown")
        XCTAssertTrue(element(labelContaining: "satisfies the defined criteria").exists, "result is worded as an assessment")
        tap(app.buttons["Done"].firstMatch)

        tap(app.tabBars.buttons["Progress"])
        XCTAssertTrue(element(labelContaining: "Verified by AI").waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContaining: "Verified by AI, 1").exists || element(labelContaining: "Verified by AI 1").exists,
                      "progress counts the verified completion")
    }

    // MARK: Flow 2: Dashboard → Skip a skill → Accept 50 push-ups → Camera → Complete exercise → Resolved → Streak

    func testSkipAccountabilityFlow() {
        registerAndOnboard()
        setUpChallenge()

        tap(app.buttons["commitment.row.Spanish"])
        tap(app.buttons["habit.skip"])
        XCTAssertTrue(element(labelContaining: "PUSH-UPS").waitForExistence(timeout: 5), "consequence shown before accepting")
        tap(app.buttons["skip.accept"])
        tap(app.navigationBars.buttons.element(boundBy: 0))

        tap(app.buttons["accountability.start"])
        XCTAssertTrue(app.buttons["exercise.done"].waitForExistence(timeout: 60), "scripted session reaches the target")
        XCTAssertTrue(element(labelContaining: "Computer vision detected 50 repetitions").exists)
        tap(app.buttons["exercise.done"])

        XCTAssertFalse(app.buttons["accountability.start"].waitForExistence(timeout: 3), "task resolved")
        tap(app.tabBars.buttons["Streak"])
        XCTAssertTrue(element(labelContaining: "DAY STREAK").waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func registerAndOnboard() {
        tap(app.buttons["welcome.register"])
        type("UI Tester", into: app.textFields["register.name"])
        type("uitest@example.com", into: app.textFields["register.email"])
        type("Discipline2026", into: app.secureTextFields["register.password"])
        type("Discipline2026", into: app.secureTextFields["register.confirmPassword"])
        tap(app.buttons["register.submit"])

        tap(app.buttons["Skip intro"])
        tap(app.buttons["onboarding.next"])
        tap(app.buttons["rules.accountability"])
        tap(app.buttons["rules.ai"])
        tap(app.buttons["rules.research"])
        tap(app.buttons["rules.accept"])
    }

    /// Default routine (4 workouts, 2 runs) plus two daily skills, starting today.
    private func setUpChallenge() {
        tap(app.buttons["setup.next"])   // intro
        tap(app.buttons["setup.next"])   // weekly routine (defaults)
        type("Guitar", into: app.textFields["setup.skill1"])
        type("Spanish", into: app.textFields["setup.skill2"])
        tap(app.buttons["setup.next"])   // skills
        tap(app.buttons["setup.next"])   // extras (none)
        tap(app.buttons["setup.accept"])
        tap(app.buttons["setup.start"])
        XCTAssertTrue(app.buttons["commitment.row.Guitar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["commitment.row.Spanish"].exists)
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)", file: file, line: line)
        element.tap()
    }

    private func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        tap(field, file: file, line: line)
        field.typeText(text)
    }

    private func element(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }
}
