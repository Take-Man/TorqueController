import AppKit

/// 切替キーの背景。ハイライトがキーの文字の下を滑れるよう、キーとは別に描く。
final class ModeBackgroundView: NSView {
    var keyFrames: [NSRect] = []
    var isDimmed = false {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setAlpha(isDimmed ? KeyView.dimmedAlpha : 1)
        NSColor.controlColor.setFill()
        for frame in keyFrames {
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        }
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
    var symbolSize: CGFloat = 18
    var cornerRadius: CGFloat = 8
    /// 枠と文字の色で示す印。背景を塗らないので、押したときの反応と紛れない。
    var isMarked = false {
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
    /// 変換中など、今は使わないキーの明度を下げる。
    var isDimmed = false {
        didSet { needsDisplay = true }
    }
    /// false なら背景を描かない(背景を別のビューが受け持つ切替キー用)。
    var fillsBackground = true
    /// 押している間、キーの外へ出ても押された表示を保つ(フリック用)。
    var keepsPressedOutside = false

    /// 押した位置(画面座標)を渡す。
    var onBegin: (@MainActor (NSPoint) -> Void)?
    /// 押した位置からの移動量を渡す。
    var onDrag: (@MainActor (CGVector) -> Void)?
    /// 押した位置からの移動量と、離した位置がキーの中かどうかを渡す。
    var onEnd: (@MainActor (CGVector, Bool) -> Void)?

    private static let trackingInterval: TimeInterval = 1.0 / 60
    /// 不透明なパネルの上に重ねるので、不透明度を下げると明度が下がって見える。
    static let dimmedAlpha: CGFloat = 0.3

    private var isPressed = false {
        didSet { needsDisplay = true }
    }
    private var isTracking = false
    private var startLocation = NSPoint.zero
    private var trackingTimer: Timer?

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

    /// カーソルがパネルの外へ出ても確実に追えるよう、イベントに加えて画面上の位置とボタンの状態を定期的に調べる。
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTracking = true
        isPressed = true
        clickCount = event.clickCount
        startLocation = NSEvent.mouseLocation
        onBegin?(startLocation)
        let timer = Timer(timeInterval: Self.trackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.finishTracking()
                } else {
                    self.updateTracking()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        updateTracking()
    }

    override func mouseUp(with event: NSEvent) {
        finishTracking()
    }

    private func updateTracking() {
        guard isTracking else { return }
        isPressed = keepsPressedOutside || cursorIsInside
        onDrag?(cursorOffset)
    }

    private func finishTracking() {
        guard isTracking else { return }
        isTracking = false
        trackingTimer?.invalidate()
        trackingTimer = nil
        isPressed = false
        onEnd?(cursorOffset, cursorIsInside)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setAlpha(isDimmed ? Self.dimmedAlpha : 1)
        if fillsBackground || isPressed {
            let background: NSColor = isPressed || isSelected ? .controlAccentColor : .controlColor
            background.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        var color: NSColor = isPressed || isSelected ? .white : (isEnabled || isDimmed ? .labelColor : .tertiaryLabelColor)
        if isMarked {
            if !isPressed {
                color = .controlAccentColor
            }
            NSColor.controlAccentColor.setStroke()
            let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            frame.lineWidth = 2
            frame.stroke()
        }
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
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        // NSImage はコンテキストの不透明度を無視するので、ここで指定する
        image.draw(
            in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: isDimmed ? Self.dimmedAlpha : 1
        )
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

    private var cursorIsInside: Bool {
        guard let window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return bounds.contains(convert(inWindow, from: nil))
    }

    private var cursorOffset: CGVector {
        let location = NSEvent.mouseLocation
        return CGVector(dx: location.x - startLocation.x, dy: location.y - startLocation.y)
    }
}
