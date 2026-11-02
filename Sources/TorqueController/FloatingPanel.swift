import AppKit

/// クリックしても入力先のフォーカスを奪わないパネル。
final class FloatingPanel: NSPanel {
    /// 右クリックされたとき。全てのパネルで共通。
    static var onRightClick: (@MainActor (NSEvent, NSView) -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 右クリックはキーに届けず、ここで受ける。左ボタンでキーを押している間は何もしない。
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .rightMouseDown else {
            super.sendEvent(event)
            return
        }
        if NSEvent.pressedMouseButtons & 1 == 0, let contentView {
            Self.onRightClick?(event, contentView)
        }
    }

    /// 倍率をかけて置く。中身は logicalSize の座標のまま描くので、倍率はビューの bounds で与える。
    func place(origin: NSPoint, logicalSize: NSSize, scale: CGFloat) {
        setFrame(NSRect(x: origin.x, y: origin.y, width: logicalSize.width * scale, height: logicalSize.height * scale), display: false)
        contentView?.setBoundsSize(logicalSize)
        contentView?.needsDisplay = true
    }
}

/// パネルの土台。ドラッグでパネルが動かないようにする。
final class PanelBackgroundView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}

/// パネルの余白に置く、パネルを掴むための持ち手。6個の点を描く。
final class GripView: NSView {
    private static let dotDiameter: CGFloat = 3
    private static let dotSpacing: CGFloat = 7

    /// true なら縦に長い配置(2列×3行)。false なら横に長い配置(3列×2行)。
    var isVertical = false
    /// 動かしている間。
    var onDrag: (@MainActor () -> Void)?
    /// 動かし終えたとき。パネルの左下の位置を渡す。
    var onEnd: (@MainActor (NSPoint) -> Void)?
    /// 動かさずにクリックしたとき。
    var onClick: (@MainActor (NSView) -> Void)?
    /// 動かせる範囲の制限。
    var constrain: (@MainActor (NSPoint) -> NSPoint)?

    private static let clickSlop: CGFloat = 3
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var hasDragged = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        hasDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        if !hasDragged, hypot(mouse.x - startMouse.x, mouse.y - startMouse.y) < Self.clickSlop {
            return
        }
        hasDragged = true
        let origin = NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y)
        window?.setFrameOrigin(constrain?(origin) ?? origin)
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        if !hasDragged {
            onClick?(self)
        } else if let origin = window?.frame.origin {
            onEnd?(origin)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        let columns = isVertical ? 2 : 3
        let rows = isVertical ? 3 : 2
        for column in 0..<columns {
            for row in 0..<rows {
                let x = bounds.midX + (CGFloat(column) - CGFloat(columns - 1) / 2) * Self.dotSpacing - Self.dotDiameter / 2
                let y = bounds.midY + (CGFloat(row) - CGFloat(rows - 1) / 2) * Self.dotSpacing - Self.dotDiameter / 2
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: Self.dotDiameter, height: Self.dotDiameter)).fill()
            }
        }
    }
}
