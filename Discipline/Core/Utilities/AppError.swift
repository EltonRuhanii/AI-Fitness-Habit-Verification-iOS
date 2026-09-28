import Foundation

/// User-presentable error. Every service error is mapped to one of these so views never
/// show raw SDK messages and never fail silently.
enum AppError: LocalizedError, Equatable {
    case offline
    case invalidCredentials
    case emailAlreadyInUse
    case invalidEmail
    case weakPassword
    case accountDisabled
    case tooManyRequests
    case requiresRecentLogin
    case permissionDenied
    case notFound
    case validation(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You're offline. Check your connection and try again."
        case .invalidCredentials:
            return "Email or password is incorrect."
        case .emailAlreadyInUse:
            return "An account with this email already exists. Try signing in instead."
        case .invalidEmail:
            return "That email address isn't valid."
        case .weakPassword:
            return "That password is too weak. Use at least 8 characters with letters and numbers."
        case .accountDisabled:
            return "This account has been disabled."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        case .requiresRecentLogin:
            return "For your security, sign out and sign in again before doing this."
        case .permissionDenied:
            return "You don't have permission to do that."
        case .notFound:
            return "We couldn't find what you were looking for."
        case .validation(let message):
            return message
        case .unknown(let message):
            return message.isEmpty ? "Something went wrong. Please try again." : message
        }
    }

    /// Maps SDK errors by domain/code so this type doesn't depend on Firebase modules and
    /// stays stable across SDK versions.
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError

        switch nsError.domain {
        case "FIRAuthErrorDomain":
            switch nsError.code {
            case 17004, 17009, 17011: return .invalidCredentials
            case 17005: return .accountDisabled
            case 17007: return .emailAlreadyInUse
            case 17008: return .invalidEmail
            case 17010: return .tooManyRequests
            case 17014: return .requiresRecentLogin
            case 17020: return .offline
            case 17026: return .weakPassword
            default: break
            }
        case "FIRFirestoreErrorDomain":
            switch nsError.code {
            case 5: return .notFound
            case 7, 16: return .permissionDenied
            case 14: return .offline
            default: break
            }
        case NSURLErrorDomain:
            return .offline
        default:
            break
        }
        return .unknown(nsError.localizedDescription)
    }
}
