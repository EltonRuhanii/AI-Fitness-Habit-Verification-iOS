import Foundation
import FirebaseAuth

@MainActor
final class FirebaseAuthenticationService: AuthenticationService {
    private let auth: Auth

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    var currentUser: AuthUser? {
        auth.currentUser.map(AuthUser.init(firebaseUser:))
    }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            // Firebase restores the persisted session on launch and calls this listener
            // with the restored user, which gives us persistent authentication.
            let handle = auth.addStateDidChangeListener { _, user in
                continuation.yield(user.map(AuthUser.init(firebaseUser:)))
            }
            continuation.onTermination = { [auth] _ in
                auth.removeStateDidChangeListener(handle)
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await auth.signIn(withEmail: normalized(email), password: password)
            return AuthUser(firebaseUser: result.user)
        } catch {
            throw AppError.from(error)
        }
    }

    func register(email: String, password: String, displayName: String) async throws -> AuthUser {
        do {
            let result = try await auth.createUser(withEmail: normalized(email), password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
            return AuthUser(uid: result.user.uid, email: result.user.email, displayName: displayName)
        } catch {
            throw AppError.from(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: normalized(email))
        } catch {
            throw AppError.from(error)
        }
    }

    func signOut() throws {
        do {
            try auth.signOut()
        } catch {
            throw AppError.from(error)
        }
    }

    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else { return }
        do {
            try await user.delete()
        } catch {
            throw AppError.from(error)
        }
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension AuthUser {
    init(firebaseUser user: User) {
        self.init(uid: user.uid, email: user.email, displayName: user.displayName)
    }
}
