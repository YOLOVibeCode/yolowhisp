import Foundation

public protocol HotkeyRecording {
    func startRecording(completion: @escaping (HotkeyConfig) -> Void)
    func cancelRecording()
}
