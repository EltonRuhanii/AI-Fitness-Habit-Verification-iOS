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
    private var profileTask: Task<Void, Never>?
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
        profileTask?.cancel()
        profileTask = nil
        guard let user else {
            phase = .signedOut
            return
        }
        do {
            let profile = try await loadOrCreateProfile(for: user)
            // Ignore stale results if the user signed out or switched accounts meanwhile.
            guard lastUser?.uid == user.uid else { return }
            apply(profile)
            observeProfile(uid: user.uid)
            await syncTimeZone(profile)
        } catch {
            guard lastUser?.uid == user.uid else { return }
            phase = .failed(AppError.from(error))
        }
    }

    private func apply(_ profile: UserProfile) {
        phase = profile.onboardingCompleted ? .ready(profile) : .onboarding(profile)
    }

    /// Keeps the session in sync with server-side profile changes (e.g. condition assignment).
    private func observeProfile(uid: String) {
        profileTask = Task { [weak self, users] in
            do {
                for try await profile in users.observeProfile(uid: uid) {
                    guard let self, self.lastUser?.uid == uid, let profile else { continue }
                    if profile != self.profile { self.apply(profile) }
                }
            } catch {
                Log.data.error("Profile updates stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Research days are resolved in the participant's local calendar; keep the zone current.
    private func syncTimeZone(_ profile: UserProfile) async {
        let current = TimeZone.current.identifier
        guard profile.timeZone != current else { return }
        try? await updateProfile { $0.timeZone = current }
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
            trackingCondition: ConditionAssignment.provisional(),
            timeZone: TimeZone.current.identifier
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

    /// Deletes the identity. With Firebase, the `onUserDeleted` Cloud Function then removes the
    /// profile, all user-owned documents, evidence photos and research records.
    func deleteAccount() async throws {
        guard let uid = profile?.id else { return }
        try await users.prepareForAccountDeletion(uid: uid)
        try await auth.deleteCurrentUser()
    }

    private static func fallbackName(from email: String?) -> String {
        guard let local = email?.split(separator: "@").first, !local.isEmpty else { return "Athlete" }
        return local.prefix(1).uppercased() + local.dropFirst()
    }
}

/// Provisional experimental condition written with a new profile.
///
/// With Firebase, `onUserProfileCreated` immediately replaces it with a server-side permuted-block
/// assignment (recorded in `conditionAssignedBy`) before onboarding finishes; the session observes
/// the profile and picks that up. In demo mode this random value is final.
enum ConditionAssignment {
    static func provisional() -> TrackingCondition {
        AppConfiguration.current.forcedCondition ?? (Bool.random() ? .manual : .aiAssisted)
    }
}
