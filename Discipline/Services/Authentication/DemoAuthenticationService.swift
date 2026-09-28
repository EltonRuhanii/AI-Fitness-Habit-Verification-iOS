import Foundation
import DisciplineCore

/// Local authentication for demo mode and UI tests.
///
/// Passwords are validated for shape but never stored: any well-formed password signs in
/// to a local demo account. This is intentionally *not* a security boundary and is never
/// used when Firebase is configured.
@MainActor
final class DemoAuthenticationService: AuthenticationService {
    private static let sessionKey = "demo.auth.session"

    private let defaults: UserDefaults
    private var continuations: [UUID: AsyncStream<AuthUser?>.Continuation] = [:]
    private(set) var currentUser: AuthUser? {
        didSet {
            persist()
            continuations.values.forEach { $0.yield(currentUser) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.sessionKey),
           let stored = try? JSONDecoder().decode(StoredUser.self, from: data) {
            currentUser = AuthUser(uid: stored.uid, email: stored.email, displayName: stored.displayName)
        }
    }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(currentUser)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        if let issue = CredentialValidator.validateEmail(email) { throw AppError.validation(issue.message) }
        guard !password.isEmpty else { throw AppError.invalidCredentials }
        try await Task.sleep(for: .milliseconds(350))
        let user = AuthUser(uid: Self.uid(for: email), email: email.lowercased(), displayName: nil)
        currentUser = user
        return user
    }

    func register(email: String, password: String, displayName: String) async throws -> AuthUser {
        if let issue = CredentialValidator.validateRegistration(displayName: displayName, email: email, password: password, confirmation: password) {
            throw AppError.validation(issue.message)
        }
        try await Task.sleep(for: .milliseconds(350))
        let user = AuthUser(uid: Self.uid(for: email), email: email.lowercased(), displayName: displayName)
        currentUser = user
        return user
    }

    func sendPasswordReset(email: String) async throws {
        if let issue = CredentialValidator.validateEmail(email) { throw AppError.validation(issue.message) }
        try await Task.sleep(for: .milliseconds(250))
    }

    func signOut() throws {
        currentUser = nil
    }

    func deleteCurrentUser() async throws {
        currentUser = nil
    }

    /// Demo mode has no researcher accounts; the research screen shows local data instead.
    func isResearcher() async -> Bool { false }

    /// Stable per-email uid so signing back in restores the same local demo data.
    private static func uid(for email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "demo-" + String(hash, radix: 16)
    }

    private func persist() {
        if let currentUser {
            let stored = StoredUser(uid: currentUser.uid, email: currentUser.email, displayName: currentUser.displayName)
            defaults.set(try? JSONEncoder().encode(stored), forKey: Self.sessionKey)
        } else {
            defaults.removeObject(forKey: Self.sessionKey)
        }
    }

    private struct StoredUser: Codable {
        let uid: String
        let email: String?
        let displayName: String?
    }
}
