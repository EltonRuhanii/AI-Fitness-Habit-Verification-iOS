import Foundation
import FirebaseFirestore

enum FirestoreSupport {
    /// Live query results as an async stream. Served from the offline cache first, then kept
    /// up to date. Documents that fail to decode are logged and skipped, never silently lost.
    static func stream<T: Decodable>(_ query: Query, as type: T.Type) -> AsyncThrowingStream<[T], Error> {
        AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: AppError.from(error))
                    return
                }
                guard let snapshot else { return }
                let values: [T] = snapshot.documents.compactMap { document in
                    do {
                        return try document.data(as: T.self)
                    } catch {
                        Log.data.error("Could not decode \(document.reference.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
                continuation.yield(values)
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    /// Writes locally and returns immediately. The server acknowledgement (or failure) is
    /// reported to the sync monitor, so the UI stays responsive offline.
    @MainActor
    static func set<T: Encodable>(_ value: T, at reference: DocumentReference, monitor: SyncMonitor) throws {
        let data: [String: Any]
        do {
            data = try Firestore.Encoder().encode(value)
        } catch {
            throw AppError.unknown("Could not prepare data for saving.")
        }
        monitor.writeStarted()
        reference.setData(data) { error in
            Task { @MainActor in monitor.writeFinished(error: error) }
        }
    }
}
