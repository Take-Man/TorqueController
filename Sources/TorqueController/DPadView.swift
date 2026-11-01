import AppKit

enum ArrowDirection: CaseIterable {
    case up, down, left, right

    var key: TextSender.Key {
        switch self {
        case .up: .upArrow
        case .down: .downArrow
        case .left: .leftArrow
        case .right: .rightArrow
        }
    }

    var symbol: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
    }

    /// 円を上下左右それぞれ三分割した、十字の形のブロックだけに方向がある。中央と四隅は反応しない。
    static func at(offset: CGVector, radius: CGFloat) -> ArrowDirection? {
        guard hypot(offset.dx, offset.dy) <= radius else { return nil }
        let third = radius / 3
        if abs(offset.dx) <= third {
            if offset.dy > third { return .up }
            if offset.dy < -third { return .down }
        } else if abs(offset.dy) <= third {
            return offset.dx > 0 ? .right : .left
        }
        return nil
    }
}

/// 十字キー。押している間、カーソルの下のブロックの方向を送り続ける。押したままの状態は残さない。
final class DPadView: NSView {
    private static let repeatDelay: TimeInterval = 0.35
    private static let repeatInterval: TimeInterval = 0.05

    /// 方向を1回送るとき。
    var onArrow: (@MainActor (ArrowDirection) -> Void)?
    /// 離したとき。
    var onRelease: (@MainActor () -> Void)?
    var isEnabled = true {
        didSet { needsDisplay = true }
    }

    private var pressed: ArrowDirection? {
        didSet {
            if pressed != oldValue { needsDisplay = true }
        }
    }
    private var repeatTimer: Timer?

    private var radius: CGFloat { min(bounds.width, bounds.height) / 2 }
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        moveTo(event)
        let timer = Timer(
            fire: Date().addingTimeInterval(Self.repeatDelay),
            interval: Self.repeatInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeatTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        guard repeatTimer != nil else { return }
        moveTo(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard repeatTimer != nil else { return }
        stop()
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        NSGraphicsContext.saveGraphicsState()
        NSColor.controlColor.withAlphaComponent(0.25).setFill()
        circle.fill()
        circle.addClip()
        for direction in ArrowDirection.allCases {
            let block = blockRect(direction)
            (pressed == direction ? NSColor.controlAccentColor : NSColor.controlColor).setFill()
            NSBezierPath(roundedRect: block, xRadius: 4, yRadius: 4).fill()
            drawArrow(direction, in: block)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func blockRect(_ direction: ArrowDirection) -> NSRect {
        let third = radius * 2 / 3
        let inset: CGFloat = 1
        let half = third / 2
        // 円の外まで伸ばして、円で切り取る
        switch direction {
        case .up: return NSRect(x: center.x - half + inset, y: center.y + half + inset, width: third - inset * 2, height: radius)
        case .down: return NSRect(x: center.x - half + inset, y: center.y - half - radius - inset, width: third - inset * 2, height: radius)
        case .left: return NSRect(x: center.x - half - radius - inset, y: center.y - half + inset, width: radius, height: third - inset * 2)
        case .right: return NSRect(x: center.x + half + inset, y: center.y - half + inset, width: radius, height: third - inset * 2)
        }
    }

    private func drawArrow(_ direction: ArrowDirection, in block: NSRect) {
        let color: NSColor = pressed == direction ? .white : (isEnabled ? .labelColor : .tertiaryLabelColor)
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: direction.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let distance = radius * 2 / 3
        var point = center
        switch direction {
        case .up: point.y += distance
        case .down: point.y -= distance
        case .left: point.x -= distance
        case .right: point.x += distance
        }
        let size = image.size
        image.draw(in: NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height))
    }

    /// 別のブロックへ移ったら、すぐにその方向を送る。
    private func moveTo(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let direction = ArrowDirection.at(offset: CGVector(dx: point.x - center.x, dy: point.y - center.y), radius: radius)
        if direction != pressed, let direction {
            onArrow?(direction)
        }
        pressed = direction
    }

    private func repeatTick() {
        // 離すイベントを受け取れなかったときも、送り続けない
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            stop()
            return
        }
        if let pressed {
            onArrow?(pressed)
        }
    }

    private func stop() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressed = nil
        onRelease?()
    }
}
