import Foundation

public protocol UpdateChecking: AnyObject {
    func checkForUpdates()
    var canCheckForUpdates: Bool { get }
}
