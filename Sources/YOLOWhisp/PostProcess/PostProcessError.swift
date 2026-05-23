import Foundation

public enum PostProcessError: Error {
    case networkError(String)
    case invalidResponse
    case apiError(String)
    case noAPIKey
}
