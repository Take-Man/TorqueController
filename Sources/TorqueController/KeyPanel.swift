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

/// パネルの土台。ドラッグでパネルが動かないようにする。
final class PanelBackgroundView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}

final class KeyView: NSView {
    var label: String {
        didSet { needsDisplay = true }
    }
    /// 文字の代わりに表示する SF Symbols の名前。
    var symbolName: String? {
        didSet { needsDisplay = true }
    }
    /// 上下左右に小さく表示する文字。
    var hints: [FlickDirection: String] = [:] {
        didSet { needsDisplay = true }
    }
    /// 最後に離したときの連続クリック数。
    private(set) var clickCount = 1
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    var isEnabled = true {
        didSet { needsDisplay = true }
    }
    /// 押している間、キーの外へ出ても押された表示を保つ(フリック用)。
    var keepsPressedOutside = false

    /// 押した位置(画面座標)を渡す。
    var onBegin: (@MainActor (NSPoint) -> Void)?
    /// 押した位置からの移動量を渡す。
    var onDrag: (@MainActor (CGVector) -> Void)?
    /// 押した位置からの移動量と、離した位置がキーの中かどうかを渡す。
    var onEnd: (@MainActor (CGVector, Bool) -> Void)?

    private var isPressed = false {
        didSet { needsDisplay = true }
    }
    private var isTracking = false
    private var startLocation = NSPoint.zero

    init(label: String = "", symbolName: String? = nil) {
        self.label = label
        self.symbolName = symbolName
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        isTracking = true
        isPressed = true
        startLocation = event.locationInWindow
        onBegin?(window.convertPoint(toScreen: startLocation))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking else { return }
        isPressed = keepsPressedOutside || contains(event)
        onDrag?(offset(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        isPressed = false
        clickCount = event.clickCount
        onEnd?(offset(of: event), contains(event))
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = isPressed || isSelected ? .controlAccentColor : .controlColor
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let color: NSColor = isPressed || isSelected ? .white : (isEnabled ? .labelColor : .tertiaryLabelColor)
        if let symbolName {
            drawSymbol(symbolName, color: color)
        } else {
            drawLabel(color: color)
        }
        drawHints(color: color)
    }

    private func drawLabel(color: NSColor) {
        var fontSize: CGFloat = label.count > 2 ? 15 : 22
        let attributes = { (size: CGFloat) -> [NSAttributedString.Key: Any] in
            [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        }
        // キーの幅に収まらないときは文字を小さくする
        let availableWidth = bounds.width - 8
        let width = NSAttributedString(string: label, attributes: attributes(fontSize)).size().width
        if width > availableWidth {
            fontSize *= availableWidth / width
        }
        let text = NSAttributedString(string: label, attributes: attributes(fontSize))
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    private func drawSymbol(_ name: String, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }

    private func drawHints(color: NSColor) {
        for (direction, hint) in hints {
            let text = NSAttributedString(string: hint, attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: color.withAlphaComponent(0.7),
            ])
            let size = text.size()
            let inset: CGFloat = 4
            let origin = switch direction {
            case .left: NSPoint(x: inset, y: bounds.midY - size.height / 2)
            case .right: NSPoint(x: bounds.maxX - inset - size.width, y: bounds.midY - size.height / 2)
            case .up: NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - inset / 2 - size.height)
            case .down: NSPoint(x: bounds.midX - size.width / 2, y: inset / 2)
            }
            text.draw(at: origin)
        }
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func offset(of event: NSEvent) -> CGVector {
        CGVector(dx: event.locationInWindow.x - startLocation.x, dy: event.locationInWindow.y - startLocation.y)
    }
}

/// キーボードの上端に出す未確定文字列。長いときは末尾が見えるように先頭を省略する。
final class CompositionView: NSView {
    var text = "" {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        let height = string.size().height
        string.draw(in: NSRect(x: 8, y: bounds.midY - height / 2, width: bounds.width - 16, height: height))
    }
}
