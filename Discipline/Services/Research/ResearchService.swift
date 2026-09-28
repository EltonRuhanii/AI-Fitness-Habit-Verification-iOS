import Foundation
import FirebaseFirestore
import FirebaseFunctions
import DisciplineCore

struct ResearchExport: Sendable {
    let dailyCSV: String
    /// Completion-level events; only available from the study backend.
    let eventsCSV: String?
}

@MainActor
protocol ResearchService: AnyObject {
    /// Whether this backend serves real, multi-participant study data.
    var isStudyData: Bool { get }
    func loadRecords() async throws -> [DailyRecord]
    func export() async throws -> ResearchExport
}

/// Researcher access to the study backend. Firestore rules only allow reading `dailyRecords`
/// with the `researcher` claim; the export callable checks the same claim.
@MainActor
final class FirebaseResearchService: ResearchService {
    private let db: Firestore
    private let functions: Functions

    init(db: Firestore = Firestore.firestore(), functions: Functions = Functions.functions()) {
        self.db = db
        self.functions = functions
    }

    let isStudyData = true

    func loadRecords() async throws -> [DailyRecord] {
        do {
            let snapshot = try await db.collection(Collections.dailyRecords).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: DailyRecord.self) }
        } catch {
            throw AppError.from(error)
        }
    }

    func export() async throws -> ResearchExport {
        let callable = functions.httpsCallable("exportResearchCsv")
        callable.timeoutInterval = 300
        do {
            let result = try await callable.call([String: Any]())
            guard let data = result.data as? [String: Any], let daily = data["daily"] as? String else {
                throw AppError.unknown("The export couldn't be read.")
            }
            return ResearchExport(dailyCSV: daily, eventsCSV: data["events"] as? String)
        } catch {
            throw AppError.from(error)
        }
    }
}

/// Demo mode: research views over the local participant's own data, computed on device with
/// the same record builder the server mirrors.
@MainActor
final class LocalResearchService: ResearchService {
    private let records: () -> [DailyRecord]

    init(records: @escaping () -> [DailyRecord]) {
        self.records = records
    }

    let isStudyData = false

    func loadRecords() async throws -> [DailyRecord] {
        records()
    }

    func export() async throws -> ResearchExport {
        ResearchExport(dailyCSV: ResearchCSV.daily(records()), eventsCSV: nil)
    }
}
