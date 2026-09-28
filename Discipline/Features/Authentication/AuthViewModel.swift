import Foundation
import Observation
import DisciplineCore

@MainActor
@Observable
final class AuthViewModel {
    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var infoMessage: String?

    private let auth: AuthenticationService
    private let session: SessionStore

    init(auth: AuthenticationService, session: SessionStore) {
        self.auth = auth
        self.session = session
    }

    var canSignIn: Bool { !email.isEmpty && !password.isEmpty && !isLoading }
    var canRegister: Bool { !displayName.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && !isLoading }

    func signIn() async {
        if let issue = CredentialValidator.validateEmail(email) {
            errorMessage = issue.message
            return
        }
        await perform {
            _ = try await self.auth.signIn(email: self.email, password: self.password)
        }
    }

    func register() async {
        if let issue = CredentialValidator.validateRegistration(displayName: displayName, email: email, password: password, confirmation: confirmPassword) {
            errorMessage = issue.message
            return
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            try await self.session.register(email: self.email, password: self.password, displayName: name)
        }
    }

    func sendPasswordReset() async {
        if let issue = CredentialValidator.validateEmail(email) {
            errorMessage = issue.message
            return
        }
        await perform {
            try await self.auth.sendPasswordReset(email: self.email)
            // Same message whether or not the account exists, to avoid account enumeration.
            self.infoMessage = "If an account exists for \(self.email), you'll receive a reset link shortly."
        }
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
