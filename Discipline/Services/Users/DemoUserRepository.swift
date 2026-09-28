import Foundation
import DisciplineCore

/// Demo-mode profile storage. Kept in its own file under Application Support so demo data
/// is physically separate from anything Firebase caches.
@MainActor
final class DemoUserRepository: UserRepository {
    private let store: LocalJSONStore<[String: UserProfile]>
    private var profiles: [String: UserProfile]

    init(store: LocalJSONStore<[String: UserProfile]> = LocalJSONStore(fileName: "demo-users.json")) {
        self.store = store
        self.profiles = store.load() ?? [:]
    }

    func fetchProfile(uid: String) async throws -> UserProfile? {
        profiles[uid]
    }

    func createProfile(_ profile: UserProfile) async throws {
        profiles[profile.id] = profile
        try store.save(profiles)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        profiles[profile.id] = profile
        try store.save(profiles)
    }

    func deleteProfile(uid: String) async throws {
        profiles[uid] = nil
        try store.save(profiles)
    }
}
