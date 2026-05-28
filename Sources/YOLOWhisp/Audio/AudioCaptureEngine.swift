import AVFoundation
import CoreAudio
import AudioToolbox

public final class AudioCaptureEngine: AudioCapturing {
    public static let targetSampleRate: Double = 16000.0
    public static let targetChannels: AVAudioChannelCount = 1

    public private(set) var isCapturing: Bool = false
    public var audioLevelCallback: ((Float) -> Void)?

    /// Optional audio device ID for mic selection (e.g., Scarlett 2i2).
    /// Set before calling startCapture(). nil = system default.
    public var deviceID: AudioDeviceID?

    private var audioEngine = AVAudioEngine()
    private var buffers: [Data] = []
    private let bufferLock = NSLock()

    public init() {}

    public func startCapture() {
        guard !isCapturing else { return }

        // Recreate the engine each time so its input node binds to the CURRENT
        // default input device. A long-lived engine stays stuck on whatever was
        // default when it was created, so a mic plugged in / selected later
        // (e.g. a Scarlett 2i2) would be ignored.
        audioEngine = AVAudioEngine()
        var inputNode = audioEngine.inputNode

        // If the user picked a specific device, route this engine's input to it.
        // (No selection = the fresh engine already uses the system default.)
        // If routing fails (e.g. a stale/aggregate device id → OSStatus -10851),
        // rebuild on the system default so we still capture instead of getting
        // a dead device with 0 bytes.
        if let deviceID = deviceID, !setInputDevice(deviceID, on: inputNode) {
            AppLog.error("Audio capture: could not select device \(deviceID); falling back to system default")
            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let usedDevice = Self.currentInputDevice(of: inputNode) ?? deviceID
        AppLog.info("Audio capture: device=\(usedDevice.map { "\(Self.deviceName($0) ?? "?") [\($0)]" } ?? "default/unknown"), format=\(Int(inputFormat.sampleRate))Hz/\(inputFormat.channelCount)ch")

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            AppLog.error("Audio capture: input device has no usable format (no mic / no permission?)")
            return
        }

        // Target format: 16kHz mono 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else { return }

        // Install converter if needed
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            AppLog.error("Audio capture: no converter from \(inputFormat) to 16kHz mono")
            return
        }
        // Take the FIRST input channel for our mono output. Many devices report
        // multiple input channels (e.g. the built-in mic as 4ch); the default
        // multi-channel→mono downmix can produce silence, so map explicitly.
        if inputFormat.channelCount > 1 {
            converter.channelMap = [0]
        }

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
            // Provide the input buffer exactly once. The converter may call this
            // block multiple times per convert() while resampling (e.g. 48k->16k);
            // returning the same buffer with .haveData each time re-consumes it and
            // corrupts the output. Signal .noDataNow after the first feed.
            var fed = false
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if fed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
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
            AppLog.error("Audio capture: engine failed to start: \(error)")
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

        let seconds = Double(pcmData.count) / 2.0 / Self.targetSampleRate
        AppLog.info("Audio capture stopped: \(pcmData.count) bytes (~\(String(format: "%.1f", seconds))s of 16kHz mono)")
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

    /// Route THIS engine's input to a specific device, without touching the
    /// system-wide default (the old behaviour changed it for every app).
    @discardableResult
    private func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) -> Bool {
        guard let unit = inputNode.audioUnit else {
            AppLog.error("Audio capture: input node has no audio unit; cannot select device \(deviceID)")
            return false
        }
        var dev = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &dev,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            AppLog.error("Audio capture: failed to set input device \(deviceID) (OSStatus \(status))")
            return false
        }
        return true
    }

    /// The device the input node is actually bound to (for logging/diagnostics).
    static func currentInputDevice(of inputNode: AVAudioInputNode) -> AudioDeviceID? {
        guard let unit = inputNode.audioUnit else { return nil }
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, &size
        )
        return status == noErr ? dev : nil
    }

    /// The system's current default input device.
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &dev
        )
        return (status == noErr && dev != 0) ? dev : nil
    }

    /// The input device this engine will capture from: the explicit selection,
    /// or the system default. For diagnostics / UI display.
    public func currentInputDevice() -> (id: AudioDeviceID, name: String)? {
        guard let id = deviceID ?? Self.defaultInputDeviceID() else { return nil }
        return (id, Self.deviceName(id) ?? "Unknown device")
    }

    /// Human-readable name for a CoreAudio device ID.
    static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &nameRef)
        guard status == noErr, let cf = nameRef?.takeRetainedValue() else { return nil }
        return cf as String
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
