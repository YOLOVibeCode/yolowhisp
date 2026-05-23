import Foundation

public final class PillDragController: PillDragging {
    public private(set) var isDragUnlocked: Bool = false
    public var longPressDelay: TimeInterval = 0.5

    public var onDragUnlocked: (() -> Void)?
    public var onPositionChanged: ((CGPoint) -> Void)?
    public var onDragEnded: ((CGPoint) -> Void)?

    private var longPressWorkItem: DispatchWorkItem?
    private var lastDragPoint: CGPoint = .zero

    public init() {}

    public func beginLongPress() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.isDragUnlocked = true
            self?.onDragUnlocked?()
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressDelay, execute: workItem)
    }

    public func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isDragUnlocked = false
    }

    public func drag(to point: CGPoint) {
        lastDragPoint = point
        onPositionChanged?(point)
    }

    public func endDrag() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isDragUnlocked = false
        onDragEnded?(lastDragPoint)
    }
}
