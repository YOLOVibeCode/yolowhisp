import Foundation

public protocol AudioCapturing: AnyObject {
    func startCapture()
    func stopCapture() -> Data
    var isCapturing: Bool { get }
}
