import Foundation

public enum AccountabilityTaskType: String, Codable, CaseIterable, Sendable {
    case pushUps, squats, sitUps, lunges, reading, running, coldPlunge, stretching, custom

    public var displayName: String {
        switch self {
        case .pushUps: return "Push-Ups"
        case .squats: return "Squats"
        case .sitUps: return "Sit-Ups"
        case .lunges: return "Lunges"
        case .reading: return "Reading"
        case .running: return "Running"
        case .coldPlunge: return "Cold Plunge"
        case .stretching: return "Stretching"
        case .custom: return "Custom"
        }
    }

    /// Whether the task is verified by the on-device exercise camera.
    public var isCameraVerified: Bool {
        switch self {
        case .pushUps, .squats, .sitUps, .lunges: return true
        default: return false
        }
    }

    /// Upper bound on a single consequence. Consequences must stay within reasonable,
    /// non-dangerous limits regardless of how a challenge is configured.
    public var safetyLimit: Int {
        switch self {
        case .pushUps: return 100
        case .squats: return 150
        case .sitUps: return 100
        case .lunges: return 100
        case .reading: return 100      // pages
        case .running: return 60       // minutes
        case .coldPlunge: return 5     // minutes
        case .stretching: return 30    // minutes
        case .custom: return 100
        }
    }

    public var unitName: String {
        switch self {
        case .pushUps, .squats, .sitUps, .lunges: return "reps"
        case .reading: return "pages"
        case .running, .coldPlunge, .stretching: return "minutes"
        case .custom: return "units"
        }
    }
}

public enum AccountabilityTaskStatus: String, Codable, CaseIterable, Sendable {
    case pending, inProgress, completed, failed, expired

    public var isOpen: Bool { self == .pending || self == .inProgress }
}

/// A consequence configured in advance, e.g. "skip gym → 50 push-ups within 24 h".
public struct AccountabilityTemplate: Codable, Hashable, Sendable {
    public var type: AccountabilityTaskType
    public var target: Int
    /// Hours after acceptance before the task expires. Capped so it always resolves by end of day + grace.
    public var deadlineHours: Int
    public var customTitle: String?

    public init(type: AccountabilityTaskType, target: Int, deadlineHours: Int = 24, customTitle: String? = nil) {
        self.type = type
        self.target = min(max(1, target), type.safetyLimit)
        self.deadlineHours = min(max(1, deadlineHours), 48)
        self.customTitle = customTitle
    }

    public var title: String {
        customTitle ?? "\(target) \(type.displayName)"
    }
}

public struct AccountabilityTask: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var sourceHabitId: String
    public var sourceCompletionId: String
    /// Day of the skipped commitment this task resolves.
    public var day: DayKey
    public var title: String
    public var description: String
    public var type: AccountabilityTaskType
    public var target: Int
    public var progress: Int
    public var status: AccountabilityTaskStatus
    public var createdAt: Date
    /// When the participant explicitly accepted the consequence.
    public var acceptedAt: Date
    public var deadline: Date
    public var completedAt: Date?
    public var exerciseSessionIds: [String]

    public init(
        id: String = UUID().uuidString,
        userId: String,
        sourceHabitId: String,
        sourceCompletionId: String,
        day: DayKey,
        title: String,
        description: String,
        type: AccountabilityTaskType,
        target: Int,
        progress: Int = 0,
        status: AccountabilityTaskStatus = .pending,
        createdAt: Date = Date(),
        acceptedAt: Date = Date(),
        deadline: Date,
        completedAt: Date? = nil,
        exerciseSessionIds: [String] = []
    ) {
        self.id = id
        self.userId = userId
        self.sourceHabitId = sourceHabitId
        self.sourceCompletionId = sourceCompletionId
        self.day = day
        self.title = title
        self.description = description
        self.type = type
        self.target = target
        self.progress = progress
        self.status = status
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
        self.deadline = deadline
        self.completedAt = completedAt
        self.exerciseSessionIds = exerciseSessionIds
    }
}
