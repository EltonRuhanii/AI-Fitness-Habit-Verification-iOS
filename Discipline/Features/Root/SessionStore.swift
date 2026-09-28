import Foundation
import Observation
import DisciplineCore

/// Owns the signed-in session and decides which top-level flow is shown.
///
/// Flow: launch → `.loading` → `.signedOut` | `.onboarding` | `.ready`.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case loading
        case signedOut
        case onboarding(UserProfile)
        case ready(UserProfile)
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading

    var profile: UserProfile? {
        switch phase {
        case .onboarding(let profile), .ready(let profile): return profile
        default: return nil
        }
    }

    private let auth: AuthenticationService
    private let users: UserRepository
    private var listenTask: Task<Void, Never>?
    private var lastUser: AuthUser?
    /// Display name captured at registration. Firebase reports the new user before the
    /// name is committed to the auth profile, so the profile is created from this instead.
    private var pendingDisplayName: String?

    init(auth: AuthenticationService, users: UserRepository) {
        self.auth = auth
        self.users = users
    }

    /// Starts observing auth state. Safe to call more than once.
    func start() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            guard let stream = self?.auth.authStateChanges() else { return }
            for await user in stream {
                await self?.handle(user)
            }
        }
    }

    func retry() {
        Task { await handle(lastUser) }
    }

    private func handle(_ user: AuthUser?) async {
        lastUser = user
        guard let user else {
            phase = .signedOut
            return
        }
        do {
            let profile = try await loadOrCreateProfile(for: user)
            // Ignore stale results if the user signed out or switched accounts meanwhile.
            guard lastUser?.uid == user.uid else { return }
            phase = profile.onboardingCompleted ? .ready(profile) : .onboarding(profile)
        } catch {
            guard lastUser?.uid == user.uid else { return }
            phase = .failed(AppError.from(error))
        }
    }

    /// The profile is normally created right after registration, but creating it lazily here
    /// also covers an app kill between the two steps and first sign-in on a new backend.
    private func loadOrCreateProfile(for user: AuthUser) async throws -> UserProfile {
        if let existing = try await users.fetchProfile(uid: user.uid) {
            return existing
        }
        let profile = UserProfile(
            id: user.uid,
            email: user.email ?? "",
            displayName: consumePendingDisplayName() ?? user.displayName ?? Self.fallbackName(from: user.email),
            trackingCondition: ConditionAssignment.assign()
        )
        try await users.createProfile(profile)
        return profile
    }

    private func consumePendingDisplayName() -> String? {
        defer { pendingDisplayName = nil }
        return pendingDisplayName
    }

    /// Registration goes through the session so there is exactly one place that creates
    /// profiles (and assigns the experimental condition).
    func register(email: String, password: String, displayName: String) async throws {
        pendingDisplayName = displayName
        do {
            _ = try await auth.register(email: email, password: password, displayName: displayName)
        } catch {
            pendingDisplayName = nil
            throw error
        }
    }

    func completeOnboarding(researchConsent: Bool) async throws {
        guard var profile else { return }
        let now = Date()
        profile.onboardingCompleted = true
        profile.rulesAcceptedAt = now
        profile.researchConsentAt = researchConsent ? now : nil
        try await users.updateProfile(profile)
        phase = .ready(profile)
    }

    func updateProfile(_ transform: (inout UserProfile) -> Void) async throws {
        guard var profile else { return }
        transform(&profile)
        try await users.updateProfile(profile)
        phase = profile.onboardingCompleted ? .ready(profile) : .onboarding(profile)
    }

    func signOut() throws {
        try auth.signOut()
    }

    /// Deletes the profile and the identity. Remaining user-owned documents and Storage
    /// objects are removed by the `onUserDeleted` Cloud Function.
    func deleteAccount() async throws {
        guard let uid = profile?.id else { return }
        try await users.deleteProfile(uid: uid)
        try await auth.deleteCurrentUser()
    }

    private static func fallbackName(from email: String?) -> String {
        guard let local = email?.split(separator: "@").first, !local.isEmpty else { return "Athlete" }
        return local.prefix(1).uppercased() + local.dropFirst()
    }
}

/// Assigns the between-subjects experimental condition.
///
/// Phase 1 assigns uniformly at random on the client. Phase 10 moves assignment to a Cloud
/// Function (balanced block randomization), after which this is only a fallback. Security
/// rules already make the condition immutable once written.
enum ConditionAssignment {
    static func assign() -> TrackingCondition {
        Bool.random() ? .manual : .aiAssisted
    }
}
