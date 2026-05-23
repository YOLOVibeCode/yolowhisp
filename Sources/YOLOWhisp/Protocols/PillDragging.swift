import Foundation

public protocol PillDragging: AnyObject {
    var isDragUnlocked: Bool { get }
    func beginLongPress()
    func cancelLongPress()
    func drag(to point: CGPoint)
    func endDrag()
}
