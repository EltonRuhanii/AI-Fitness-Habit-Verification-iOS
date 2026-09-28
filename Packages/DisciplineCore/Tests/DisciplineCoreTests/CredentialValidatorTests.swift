import XCTest
@testable import DisciplineCore

final class CredentialValidatorTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertNil(CredentialValidator.validateEmail("elton@example.com"))
        XCTAssertNil(CredentialValidator.validateEmail("  elton@example.com \n"))
        XCTAssertEqual(CredentialValidator.validateEmail("   "), .emptyEmail)
        XCTAssertEqual(CredentialValidator.validateEmail("elton"), .invalidEmail)
        XCTAssertEqual(CredentialValidator.validateEmail("elton@example"), .invalidEmail)
        XCTAssertEqual(CredentialValidator.validateEmail("@example.com"), .invalidEmail)
        XCTAssertEqual(CredentialValidator.validateEmail("a@b@c.com"), .invalidEmail)
    }

    func testPasswordValidation() {
        XCTAssertEqual(CredentialValidator.validateNewPassword("short1", confirmation: "short1"), .passwordTooShort)
        XCTAssertEqual(CredentialValidator.validateNewPassword("onlyletters", confirmation: "onlyletters"), .passwordMissingLetterOrDigit)
        XCTAssertEqual(CredentialValidator.validateNewPassword("abcd1234", confirmation: "abcd12345"), .passwordsDoNotMatch)
        XCTAssertNil(CredentialValidator.validateNewPassword("abcd1234", confirmation: "abcd1234"))
    }

    func testRegistrationReportsFirstIssue() {
        XCTAssertEqual(CredentialValidator.validateRegistration(displayName: " ", email: "x", password: "", confirmation: ""), .emptyDisplayName)
        XCTAssertEqual(CredentialValidator.validateRegistration(displayName: "Elton", email: "x", password: "", confirmation: ""), .invalidEmail)
        XCTAssertNil(CredentialValidator.validateRegistration(displayName: "Elton", email: "e@x.io", password: "abcd1234", confirmation: "abcd1234"))
    }
}
