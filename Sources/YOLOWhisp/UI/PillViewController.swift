import Foundation

public final class PillViewController: PillDisplaying {
    public private(set) var currentState: PillState = .idle
    public private(set) var isVisible: Bool = false

    private let userDefaults: UserDefaults

    public var position: CGPoint {
        didSet {
            userDefaults.set(Double(position.x), forKey: "yolowhisp.pill.x")
            userDefaults.set(Double(position.y), forKey: "yolowhisp.pill.y")
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let x = userDefaults.double(forKey: "yolowhisp.pill.x")
        let y = userDefaults.double(forKey: "yolowhisp.pill.y")
        self.position = CGPoint(x: x, y: y)
    }

    public func show() {
        isVisible = true
    }

    public func hide() {
        isVisible = false
    }

    public func setState(_ state: PillState) {
        self.currentState = state
    }
}
