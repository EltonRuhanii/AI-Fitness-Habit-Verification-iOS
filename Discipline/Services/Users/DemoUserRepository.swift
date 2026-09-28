import Foundation
import DisciplineCore

/// Demo-mode profile storage. Kept in its own file under Application Support so demo data
/// is physically separate from anything Firebase caches.
@MainActor
final class DemoUserRepository: UserRepository {
    private let store: LocalJSONStore<[String: UserProfile]>
    private var profiles: [String: UserProfile]
    private var observers: [UUID: (uid: String, continuation: AsyncThrowingStream<UserProfile?, Error>.Continuation)] = [:]

    init(store: LocalJSONStore<[String: UserProfile]> = LocalJSONStore(fileName: "demo-users.json")) {
        self.store = store
        self.profiles = store.load() ?? [:]
    }

    func fetchProfile(uid: String) async throws -> UserProfile? {
        profiles[uid]
    }

    func createProfile(_ profile: UserProfile) async throws {
        try set(profile, for: profile.id)
    }

    func observeProfile(uid: String) -> AsyncThrowingStream<UserProfile?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            observers[id] = (uid, continuation)
            continuation.yield(profiles[uid])
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers[id] = nil }
            }
        }
    }

    func updateProfile(_ profile: UserProfile) async throws {
        // Mirror the server: the condition and participant id can't be changed by the client.
        var updated = profile
        if let existing = profiles[profile.id] {
            updated.trackingCondition = existing.trackingCondition
            updated.participantId = existing.participantId
        }
        try set(updated, for: profile.id)
    }

    func prepareForAccountDeletion(uid: String) async throws {
        try set(nil, for: uid)
    }

    private func set(_ profile: UserProfile?, for uid: String) throws {
        profiles[uid] = profile
        try store.save(profiles)
        for observer in observers.values where observer.uid == uid {
            observer.continuation.yield(profile)
        }
    }
}
