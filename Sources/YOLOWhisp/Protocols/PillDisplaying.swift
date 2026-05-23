import Foundation

public protocol PillDisplaying: AnyObject {
    func show()
    func hide()
    func setState(_ state: PillState)
    var position: CGPoint { get set }
}
