import Foundation

enum AppError: LocalizedError {
    case network(underlying: Error)
    case unauthorized
    case sessionExpired
    case serverError(code: Int, message: String)
    case invalidResponse
    case notFound
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .network:
            return "Network error. Please check your connection."
        case .unauthorized:
            return "Authentication failed. Please log in again."
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .serverError(_, let message):
            return message.isEmpty ? "Server error. Please try again." : message
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .notFound:
            return "The requested resource was not found."
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    static func wrap(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError
        if nsError.code == 401 { return .unauthorized }
        return .network(underlying: error)
    }
}
