import Foundation

public enum TextOutputError: Error, Equatable {
    case noOutputterRegistered(mode: OutputMode)
    case accessibilityNotGranted
    case noFocusedElement
    case failedToSetValue
}

public final class TextOutputManager {
    private let outputs: [OutputMode: any TextOutputting]

    public init(outputs: [OutputMode: any TextOutputting] = [:]) {
        self.outputs = outputs
    }

    public func output(text: String, mode: OutputMode) async throws {
        guard let outputter = outputs[mode] else {
            throw TextOutputError.noOutputterRegistered(mode: mode)
        }
        try await outputter.output(text: text)
    }
}
