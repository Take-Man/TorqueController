import AppKit

/// クリックしても入力先のフォーカスを奪わないパネル。
final class KeyPanel: NSPanel {
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
}

final class KeyView: NSView {
    var onPress: (() -> Void)?
    var isEnabled = true {
        didSet { needsDisplay = true }
    }

    private let label: String
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isPressed = isEnabled
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = isEnabled && contains(event)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldFire = isPressed && contains(event)
        isPressed = false
        if shouldFire {
            onPress?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = isPressed ? .controlAccentColor : .windowBackgroundColor
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        let color: NSColor = isPressed ? .white : (isEnabled ? .labelColor : .tertiaryLabelColor)
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: color,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
