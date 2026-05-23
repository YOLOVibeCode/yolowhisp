import Foundation

public protocol TextOutputting {
    func output(text: String) async throws
    var mode: OutputMode { get }
}
