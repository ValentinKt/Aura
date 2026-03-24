import Foundation

enum WeatherCondition: String, Codable, CaseIterable, Hashable {
    case clearDay
    case clearNight
    case cloudy
    case rain
    case thunderstorm
    case snow
    case windy
}

enum WeatherError: Error, LocalizedError, Equatable {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case locationUnavailable
    case unauthorized
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The weather API URL is invalid."
        case .networkError(let msg): return "Network error: \(msg)"
        case .decodingError(let msg): return "Failed to decode weather data: \(msg)"
        case .locationUnavailable: return "Location services are unavailable."
        case .unauthorized: return "Location access was denied by the user."
        case .unknown: return "An unknown error occurred."
        }
    }

    static func == (lhs: WeatherError, rhs: WeatherError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.networkError(let l), .networkError(let r)): return l == r
        case (.decodingError(let l), .decodingError(let r)): return l == r
        case (.locationUnavailable, .locationUnavailable): return true
        case (.unauthorized, .unauthorized): return true
        case (.unknown, .unknown): return true
        default: return false
        }
    }
}

enum WeatherState: Equatable {
    case idle
    case loading
    case success(WeatherCondition)
    case failure(WeatherError)
}
