import Foundation

/// Container of the app's REAL shared components, handed to the Diagnostics
/// window so it observes/exercises the same instances the dictation hotkey
/// drives — not throwaway clones.
final class AppServices {
    let controller: DictationController
    let audioCapture: AudioCaptureEngine
    let modelManager: ModelManager
    let hotkeyManager: HotkeyManager
    let permissions: any PermissionChecking
    let whisperPath: String
    /// Raw PCM for the end-to-end self-test (bundled clip), or nil.
    let sampleProvider: () -> Data?
    /// Current AI provider config when polish/dual is enabled, else nil.
    let aiConfigProvider: () -> PostProcessorConfig?

    init(
        controller: DictationController,
        audioCapture: AudioCaptureEngine,
        modelManager: ModelManager,
        hotkeyManager: HotkeyManager,
        permissions: any PermissionChecking = PermissionManager(),
        whisperPath: String = WhisperEngine.defaultWhisperPath,
        sampleProvider: @escaping () -> Data? = { DiagnosticsSamples.selfTestPCM() },
        aiConfigProvider: @escaping () -> PostProcessorConfig? = { nil }
    ) {
        self.controller = controller
        self.audioCapture = audioCapture
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager
        self.permissions = permissions
        self.whisperPath = whisperPath
        self.sampleProvider = sampleProvider
        self.aiConfigProvider = aiConfigProvider
    }
}
