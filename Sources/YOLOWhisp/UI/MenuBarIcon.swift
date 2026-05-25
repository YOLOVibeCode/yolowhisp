import AppKit

/// Available menu bar icon styles
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case whisperBubble = "whisperBubble"
    case waveform = "waveform"
    case mic = "mic"
    case ear = "ear"
    case ghost = "ghost"
    case speechBubble = "speechBubble"
    case feather = "feather"
    case wind = "wind"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperBubble: return "Whisper Bubble"
        case .waveform: return "Waveform"
        case .mic: return "Microphone"
        case .ear: return "Ear"
        case .ghost: return "Ghost"
        case .speechBubble: return "Speech Bubble"
        case .feather: return "Feather"
        case .wind: return "Wind"
        }
    }

    /// SF Symbol name if available, nil for custom-drawn icons
    var sfSymbolName: String? {
        switch self {
        case .waveform: return "waveform"
        case .mic: return "mic.fill"
        case .ear: return "ear"
        case .speechBubble: return "bubble.left.fill"
        case .wind: return "wind"
        default: return nil
        }
    }

    /// Returns an 18x18 template NSImage suitable for the menu bar
    func menuBarImage() -> NSImage {
        if let sfName = sfSymbolName {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: displayName) {
                let configured = img.withSymbolConfiguration(config) ?? img
                configured.isTemplate = true
                return configured
            }
        }
        return drawCustomIcon()
    }

    /// Returns a larger image for the settings picker preview
    func previewImage() -> NSImage {
        if let sfName = sfSymbolName {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: displayName) {
                return img.withSymbolConfiguration(config) ?? img
            }
        }
        return drawCustomIcon(size: 32)
    }

    private func drawCustomIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.set()
            switch self {
            case .whisperBubble:
                Self.drawWhisperBubble(in: rect)
            case .ghost:
                Self.drawGhost(in: rect)
            case .feather:
                Self.drawFeather(in: rect)
            default:
                // Fallback: draw a simple circle
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                path.fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Custom Icon Drawing

    /// The whisper bubble: speech bubble with three dots and a subtle smile curve
    private static func drawWhisperBubble(in rect: NSRect) {
        let s = rect.width
        let inset: CGFloat = 1
        let r = rect.insetBy(dx: inset, dy: inset + s * 0.06)
        let bubbleRect = NSRect(x: r.minX, y: r.minY + s * 0.15, width: r.width, height: r.height - s * 0.1)

        // Bubble body
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: s * 0.28, yRadius: s * 0.3)
        bubble.fill()

        // Tail (bottom-left)
        let tail = NSBezierPath()
        let tailX = bubbleRect.minX + s * 0.22
        let tailY = bubbleRect.minY
        tail.move(to: NSPoint(x: tailX, y: tailY + s * 0.04))
        tail.line(to: NSPoint(x: tailX - s * 0.08, y: tailY - s * 0.1))
        tail.line(to: NSPoint(x: tailX + s * 0.12, y: tailY + s * 0.02))
        tail.close()
        tail.fill()

        // Three dots (eyes-like)
        NSColor.white.set()
        let dotR = s * 0.055
        let dotY = bubbleRect.midY + s * 0.04
        let spacing = s * 0.17
        let centerX = bubbleRect.midX
        for dx in [-spacing, 0, spacing] {
            let dotRect = NSRect(
                x: centerX + dx - dotR,
                y: dotY - dotR,
                width: dotR * 2,
                height: dotR * 2
            )
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Smile curve below dots
        let smile = NSBezierPath()
        let smileY = dotY - s * 0.16
        smile.move(to: NSPoint(x: centerX - s * 0.12, y: smileY))
        smile.curve(
            to: NSPoint(x: centerX + s * 0.12, y: smileY),
            controlPoint1: NSPoint(x: centerX - s * 0.06, y: smileY - s * 0.1),
            controlPoint2: NSPoint(x: centerX + s * 0.06, y: smileY - s * 0.1)
        )
        smile.lineWidth = s * 0.06
        smile.lineCapStyle = .round
        smile.stroke()
    }

    /// Ghost icon — playful whisper/invisible theme
    private static func drawGhost(in rect: NSRect) {
        let s = rect.width
        let path = NSBezierPath()
        let cx = rect.midX
        let bodyTop = rect.maxY - s * 0.1
        let bodyWidth = s * 0.35

        // Head (semicircle)
        path.appendArc(
            withCenter: NSPoint(x: cx, y: bodyTop - bodyWidth),
            radius: bodyWidth,
            startAngle: 0, endAngle: 180
        )

        // Body sides down
        let bodyBottom = rect.minY + s * 0.08
        path.line(to: NSPoint(x: cx - bodyWidth, y: bodyBottom))

        // Wavy bottom
        let waveH: CGFloat = s * 0.08
        let segments = 3
        let segW = (bodyWidth * 2) / CGFloat(segments)
        for i in 0..<segments {
            let startX = cx - bodyWidth + CGFloat(i) * segW
            let endX = startX + segW
            let midX = (startX + endX) / 2
            let cpY = i % 2 == 0 ? bodyBottom + waveH : bodyBottom - waveH
            path.curve(
                to: NSPoint(x: endX, y: bodyBottom),
                controlPoint1: NSPoint(x: midX, y: cpY),
                controlPoint2: NSPoint(x: midX, y: cpY)
            )
        }

        path.close()
        path.fill()

        // Eyes
        NSColor.white.set()
        let eyeR = s * 0.055
        let eyeY = bodyTop - bodyWidth + s * 0.05
        let eyeSpacing = s * 0.12
        NSBezierPath(ovalIn: NSRect(x: cx - eyeSpacing - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + eyeSpacing - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)).fill()
    }

    /// Feather icon — light/quiet whisper theme
    private static func drawFeather(in rect: NSRect) {
        let s = rect.width
        let path = NSBezierPath()

        // Quill shape - diagonal feather
        let tip = NSPoint(x: rect.minX + s * 0.12, y: rect.minY + s * 0.08)
        let top = NSPoint(x: rect.maxX - s * 0.1, y: rect.maxY - s * 0.08)

        // Left edge
        path.move(to: tip)
        path.curve(
            to: top,
            controlPoint1: NSPoint(x: rect.minX - s * 0.05, y: rect.midY + s * 0.1),
            controlPoint2: NSPoint(x: rect.midX - s * 0.1, y: rect.maxY + s * 0.05)
        )

        // Right edge back down
        path.curve(
            to: tip,
            controlPoint1: NSPoint(x: rect.midX + s * 0.2, y: rect.maxY - s * 0.15),
            controlPoint2: NSPoint(x: rect.midX + s * 0.1, y: rect.midY - s * 0.15)
        )

        path.close()
        path.fill()

        // Central spine line
        NSColor.white.set()
        let spine = NSBezierPath()
        spine.move(to: tip)
        spine.curve(
            to: top,
            controlPoint1: NSPoint(x: rect.midX - s * 0.05, y: rect.midY),
            controlPoint2: NSPoint(x: rect.midX + s * 0.05, y: rect.midY + s * 0.2)
        )
        spine.lineWidth = s * 0.04
        spine.stroke()
    }
}
