import Foundation
import DisciplineCore

@MainActor
protocol UserRepository: AnyObject {
    func fetchProfile(uid: String) async throws -> UserProfile?
    func createProfile(_ profile: UserProfile) async throws
    /// Live profile updates, e.g. when the server assigns the experimental condition.
    func observeProfile(uid: String) -> AsyncThrowingStream<UserProfile?, Error>
    /// Updates only the fields a participant may change (never condition or participant id).
    func updateProfile(_ profile: UserProfile) async throws
    /// Called before the identity is deleted. With Firebase, the `onUserDeleted` function
    /// removes the profile, all user-owned documents, photos and research records server-side
    /// (it needs the profile to find the research records); the demo backend deletes locally.
    func prepareForAccountDeletion(uid: String) async throws
}
