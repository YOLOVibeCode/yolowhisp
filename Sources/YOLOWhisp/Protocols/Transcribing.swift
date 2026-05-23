import Foundation

public protocol Transcribing {
    func transcribe(audioData: Data) async throws -> TranscriptionResult
}
