import AppKit
import AVFoundation

/// Plays short audio cues for dictation start/stop feedback.
public final class SoundFeedback {
    public enum SoundStyle: String, CaseIterable, Identifiable {
        case tinkPop = "tinkPop"
        case pingPop = "pingPop"
        case glassPop = "glassPop"
        case morse = "morse"
        case subtle = "subtle"
        case none = "none"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .tinkPop: return "Tink / Pop"
            case .pingPop: return "Ping / Pop"
            case .glassPop: return "Glass / Pop"
            case .morse: return "Morse / Bottle"
            case .subtle: return "Subtle Tones"
            case .none: return "None"
            }
        }
    }

    public static let shared = SoundFeedback()

    private var style: SoundStyle = .tinkPop
    private var tonePlayer: AVAudioPlayer?

    private init() {}

    public var currentStyle: SoundStyle { style }

    public func setStyle(_ style: SoundStyle) {
        self.style = style
    }

    /// Play the "recording started" sound
    public func playStart() {
        switch style {
        case .tinkPop:
            playSystemSound("Tink")
        case .pingPop:
            playSystemSound("Ping")
        case .glassPop:
            playSystemSound("Glass")
        case .morse:
            playSystemSound("Morse")
        case .subtle:
            playTone(frequency: 880, duration: 0.08, volume: 0.3)
        case .none:
            break
        }
    }

    /// Play the "recording stopped" sound
    public func playStop() {
        switch style {
        case .tinkPop, .pingPop, .glassPop:
            playSystemSound("Pop")
        case .morse:
            playSystemSound("Bottle")
        case .subtle:
            playTone(frequency: 660, duration: 0.08, volume: 0.3)
        case .none:
            break
        }
    }

    // MARK: - Private

    private func playSystemSound(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop() // reset if already playing
        sound.play()
    }

    /// Generate a short sine wave tone programmatically
    private func playTone(frequency: Double, duration: Double, volume: Float) {
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * duration)

        var data = Data()
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Apply a quick fade in/out envelope to avoid clicks
            let envelope: Double
            let fadeFrames = Int(sampleRate * 0.01)
            if i < fadeFrames {
                envelope = Double(i) / Double(fadeFrames)
            } else if i > frameCount - fadeFrames {
                envelope = Double(frameCount - i) / Double(fadeFrames)
            } else {
                envelope = 1.0
            }
            let sample = sin(2.0 * .pi * frequency * t) * envelope
            var int16 = Int16(sample * Double(Int16.max) * Double(volume))
            data.append(Data(bytes: &int16, count: 2))
        }

        // Create WAV in memory
        let wavData = AudioCaptureEngine.createWAVData(
            from: data,
            sampleRate: Int(sampleRate),
            channels: 1,
            bitsPerSample: 16
        )

        tonePlayer = try? AVAudioPlayer(data: wavData)
        tonePlayer?.play()
    }
}
