import Foundation
import FirebaseFirestore
import DisciplineCore

/// Stores System Usability Scale answers. Responses are create-only and pseudonymous (participant
/// ID, no account ID); only researchers can read them, through the export.
@MainActor
protocol UsabilityRepository: AnyObject {
    func submit(_ response: SUSResponse) throws
    /// Responses submitted from this device (demo mode's research preview; nil on the study backend).
    func localResponses() -> [SUSResponse]?
}

@MainActor
final class FirestoreUsabilityRepository: UsabilityRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    func submit(_ response: SUSResponse) throws {
        try FirestoreSupport.set(response, at: db.collection(Collections.usabilityResponses).document(response.id), monitor: monitor)
    }

    func localResponses() -> [SUSResponse]? { nil }
}

@MainActor
final class DemoUsabilityRepository: UsabilityRepository {
    private let collection = DemoCollection<SUSResponse>(fileName: "demo-usability.json")

    func submit(_ response: SUSResponse) throws {
        try collection.upsert(response)
    }

    func localResponses() -> [SUSResponse]? { collection.snapshot() }
}
