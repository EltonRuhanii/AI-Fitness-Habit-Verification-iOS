import Foundation

/// Client-side input validation for authentication forms. The server (Firebase Auth)
/// remains the authority; this only gives immediate, specific feedback.
public enum CredentialValidator {
    public static let minimumPasswordLength = 8

    public enum Issue: Equatable, Sendable {
        case emptyEmail
        case invalidEmail
        case passwordTooShort
        case passwordMissingLetterOrDigit
        case passwordsDoNotMatch
        case emptyDisplayName

        public var message: String {
            switch self {
            case .emptyEmail: return "Enter your email address."
            case .invalidEmail: return "That doesn't look like a valid email address."
            case .passwordTooShort: return "Use at least \(CredentialValidator.minimumPasswordLength) characters."
            case .passwordMissingLetterOrDigit: return "Use at least one letter and one number."
            case .passwordsDoNotMatch: return "Passwords don't match."
            case .emptyDisplayName: return "Tell us what to call you."
            }
        }
    }

    public static func validateEmail(_ email: String) -> Issue? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyEmail }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !trimmed.contains(" ")
        else { return .invalidEmail }
        return nil
    }

    public static func validateNewPassword(_ password: String, confirmation: String) -> Issue? {
        guard password.count >= minimumPasswordLength else { return .passwordTooShort }
        guard password.contains(where: \.isLetter), password.contains(where: \.isNumber) else {
            return .passwordMissingLetterOrDigit
        }
        guard password == confirmation else { return .passwordsDoNotMatch }
        return nil
    }

    public static func validateRegistration(displayName: String, email: String, password: String, confirmation: String) -> Issue? {
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyDisplayName }
        return validateEmail(email) ?? validateNewPassword(password, confirmation: confirmation)
    }
}
