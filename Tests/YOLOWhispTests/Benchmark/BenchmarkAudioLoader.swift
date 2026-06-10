import AVFoundation
import Foundation

/// Loads an arbitrary audio file (wav / aiff / m4a / mp3 / caf …) and converts
/// it to the exact format the dictation pipeline expects: 16 kHz, mono,
/// 16-bit signed PCM. This lets the benchmark feed both `say`-generated samples
/// and the user's own recordings through `WhisperEngine` without any external
/// tools (ffmpeg/sox) — AVFoundation handles resampling and downmixing.
enum BenchmarkAudioLoader {

    enum LoaderError: Error, CustomStringConvertible {
        case couldNotCreateBuffer
        case couldNotCreateConverter
        case conversionFailed(String)

        var description: String {
            switch self {
            case .couldNotCreateBuffer: return "Could not allocate a PCM buffer."
            case .couldNotCreateConverter: return "Could not create an audio converter."
            case .conversionFailed(let msg): return "Audio conversion failed: \(msg)"
            }
        }
    }

    /// Returns raw 16 kHz mono Int16 PCM bytes plus the clip duration in seconds.
    static func loadPCM16kMono(url: URL) throws -> (pcm: Data, durationSeconds: Double) {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        let inputFrames = AVAudioFrameCount(file.length)
        guard inputFrames > 0 else { return (Data(), 0) }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrames) else {
            throw LoaderError.couldNotCreateBuffer
        }
        try file.read(into: inputBuffer)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw LoaderError.couldNotCreateBuffer
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw LoaderError.couldNotCreateConverter
        }
        // Take the first channel for mono so a stereo recording with a centered
        // voice doesn't get a silent/canceled downmix.
        if inputFormat.channelCount > 1 {
            converter.channelMap = [0]
        }

        let ratio = 16_000.0 / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputFrames) * ratio) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw LoaderError.couldNotCreateBuffer
        }

        var providedInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            // Feed the whole input buffer once, then signal end of stream.
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if let conversionError {
            throw LoaderError.conversionFailed(conversionError.localizedDescription)
        }

        let frames = Int(outputBuffer.frameLength)
        guard frames > 0, let channel = outputBuffer.int16ChannelData else {
            return (Data(), 0)
        }
        let pcm = Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)
        let duration = Double(frames) / 16_000.0
        return (pcm, duration)
    }
}
