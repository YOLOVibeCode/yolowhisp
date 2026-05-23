import Foundation

public protocol PostProcessing {
    func process(text: String) async throws -> String
    var providerName: String { get }
}
