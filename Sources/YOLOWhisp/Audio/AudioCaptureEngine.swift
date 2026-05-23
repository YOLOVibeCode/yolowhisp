import AVFoundation
import CoreAudio

public final class AudioCaptureEngine: AudioCapturing {
    public static let targetSampleRate: Double = 16000.0
    public static let targetChannels: AVAudioChannelCount = 1

    public private(set) var isCapturing: Bool = false
    public var audioLevelCallback: ((Float) -> Void)?

    /// Optional audio device ID for mic selection (e.g., Scarlett 2i2).
    /// Set before calling startCapture(). nil = system default.
    public var deviceID: AudioDeviceID?

    private let audioEngine = AVAudioEngine()
    private var buffers: [Data] = []
    private let bufferLock = NSLock()

    public init() {}

    public func startCapture() {
        guard !isCapturing else { return }

        if let deviceID = deviceID {
            setInputDevice(deviceID)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else { return }

        // Install converter if needed
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        bufferLock.lock()
        buffers.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Self.targetSampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.int16ChannelData {
                let frameCount = Int(convertedBuffer.frameLength)
                let byteCount = frameCount * MemoryLayout<Int16>.size
                let data = Data(bytes: channelData[0], count: byteCount)
                self.bufferLock.lock()
                self.buffers.append(data)
                self.bufferLock.unlock()

                if self.audioLevelCallback != nil {
                    let rms = Self.computeRMS(from: channelData[0], count: frameCount)
                    DispatchQueue.main.async {
                        self.audioLevelCallback?(rms)
                    }
                }
            }
        }

        do {
            try audioEngine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
        }
    }

    public func stopCapture() -> Data {
        guard isCapturing else { return Data() }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false

        bufferLock.lock()
        let pcmData = buffers.reduce(Data()) { $0 + $1 }
        buffers.removeAll()
        bufferLock.unlock()

        return pcmData
    }

    // MARK: - Audio Level

    public static func computeRMS(from pointer: UnsafePointer<Int16>, count: Int) -> Float {
        guard count > 0 else { return 0.0 }
        var sumSquares: Float = 0.0
        for i in 0..<count {
            let sample = Float(pointer[i])
            sumSquares += sample * sample
        }
        let rms = sqrtf(sumSquares / Float(count))
        return rms / 32768.0
    }

    // MARK: - WAV Utilities

    /// Creates a WAV file data from raw PCM data.
    public static func createWAVData(
        from pcmData: Data,
        sampleRate: Int = 16000,
        channels: Int = 1,
        bitsPerSample: Int = 16
    ) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        // RIFF chunk
        header.append(contentsOf: "RIFF".utf8)
        header.append(littleEndian: UInt32(fileSize))
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(littleEndian: UInt32(16))          // Sub-chunk size
        header.append(littleEndian: UInt16(1))            // PCM format
        header.append(littleEndian: UInt16(channels))
        header.append(littleEndian: UInt32(sampleRate))
        header.append(littleEndian: UInt32(byteRate))
        header.append(littleEndian: UInt16(blockAlign))
        header.append(littleEndian: UInt16(bitsPerSample))

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.append(littleEndian: UInt32(dataSize))

        return header + pcmData
    }

    // MARK: - Private

    private func setInputDevice(_ deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }
}

// MARK: - Data Extension for WAV Writing

extension Data {
    mutating func append(littleEndian value: UInt32) {
        var value = value.littleEndian
        append(Data(bytes: &value, count: MemoryLayout<UInt32>.size))
    }

    mutating func append(littleEndian value: UInt16) {
        var value = value.littleEndian
        append(Data(bytes: &value, count: MemoryLayout<UInt16>.size))
    }
}
