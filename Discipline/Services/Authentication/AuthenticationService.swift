import Foundation

/// Identity as reported by the authentication provider. Deliberately minimal — the
/// app-level profile lives in `UserProfile` (Firestore), not in the auth provider.
struct AuthUser: Equatable, Sendable {
    let uid: String
    let email: String?
    let displayName: String?
}

/// Abstraction over the identity provider so views and view models can be tested
/// without Firebase, and the app can run in demo mode.
@MainActor
protocol AuthenticationService: AnyObject {
    var currentUser: AuthUser? { get }

    /// Emits the current user immediately, then on every sign-in/sign-out.
    func authStateChanges() -> AsyncStream<AuthUser?>

    func signIn(email: String, password: String) async throws -> AuthUser
    func register(email: String, password: String, displayName: String) async throws -> AuthUser
    func sendPasswordReset(email: String) async throws
    func signOut() throws
    /// Deletes the identity. Callers delete app data first (see `SessionStore.deleteAccount`).
    func deleteCurrentUser() async throws
}
