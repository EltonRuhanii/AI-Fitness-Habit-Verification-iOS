import Foundation
import DisciplineCore

@MainActor
protocol UserRepository: AnyObject {
    func fetchProfile(uid: String) async throws -> UserProfile?
    func createProfile(_ profile: UserProfile) async throws
    func updateProfile(_ profile: UserProfile) async throws
    /// Deletes the profile document. Other user-owned collections are deleted server-side
    /// by the `onUserDeleted` Cloud Function so deletion is complete even if the app is killed.
    func deleteProfile(uid: String) async throws
}
