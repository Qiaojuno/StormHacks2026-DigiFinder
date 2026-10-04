import Foundation

enum NetworkError: Error, Equatable {
    case notConfigured, offline, badResponse, timeout
    /// Open Food Facts allows 10 searches a minute; the call was not sent.
    case rateLimited
    case http(Int)

    /// Maps transport errors to the cases the runner cares about.
    static func from(_ error: Error) -> NetworkError {
        if let e = error as? NetworkError { return e }
        if error is CancellationError { return .timeout }
        guard let u = error as? URLError else { return .badResponse }
        switch u.code {
        case .timedOut, .cancelled: return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default: return .badResponse
        }
    }
}
