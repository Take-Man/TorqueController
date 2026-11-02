import AppKit

/// 切替キーの背景。ハイライトがキーの文字の下を滑れるよう、キーとは別に描く。
final class ModeBackgroundView: NSView {
    var keyFrames: [NSRect] = []
    var isDimmed = false {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setAlpha(isDimmed ? Theme.Palette.dimmedAlpha : 1)
        Theme.Palette.key.setFill()
        for frame in keyFrames {
            NSBezierPath(roundedRect: frame, xRadius: Theme.Radius.key, yRadius: Theme.Radius.key).fill()
        }
    }
}

/// 選択中の切替キーを示す輪。切替のときにキーの文字の下を滑る。
final class ModeHighlightView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Theme.drawActive(Theme.ringPath(in: bounds, cornerRadius: Theme.Radius.key))
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
    var symbolSize = Theme.FontSize.keySymbol
    var cornerRadius = Theme.Radius.key
    /// 輪郭線と文字の色で示す印。淡い塗りがないので、押したときの反応と紛れない。
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
    /// 選択が固定されている。選択中の輪の内側にもう1本、輪を描く。
    var isLocked = false {
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
        showPressRing()
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
        NSGraphicsContext.current?.cgContext.setAlpha(isDimmed ? Theme.Palette.dimmedAlpha : 1)
        if fillsBackground {
            Theme.Palette.key.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        // fillsBackground が false のキーの選択中の輪は、ModeHighlightView が受け持つ
        if isPressed || (isSelected && fillsBackground) {
            Theme.drawActive(Theme.ringPath(in: bounds, cornerRadius: cornerRadius))
        } else if isMarked {
            Theme.drawRing(Theme.ringPath(in: bounds, cornerRadius: cornerRadius))
        }
        if isLocked {
            let inset = Theme.Line.emphasis / 2 + Theme.Space.lockedRing
            Theme.drawRing(Theme.ringPath(in: bounds, cornerRadius: cornerRadius, inset: inset))
        }

        let color: NSColor = isPressed || isSelected || isMarked
            ? Theme.Palette.accent
            : (isEnabled || isDimmed ? Theme.Palette.text : Theme.Palette.tertiaryText)
        if let symbolName {
            drawSymbol(symbolName, color: color)
        } else {
            drawLabel(color: color)
        }
        drawHints(color: color)
    }

    /// 押した瞬間の反応。キーの輪郭からアクセント色の輪が少し広がって消える。
    func showPressRing() {
        guard let layer else { return }
        func path(outset: CGFloat) -> CGPath {
            let radius = cornerRadius + outset
            return CGPath(
                roundedRect: layer.bounds.insetBy(dx: -outset, dy: -outset),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        }
        let ring = CAShapeLayer()
        ring.frame = layer.bounds
        ring.fillColor = nil
        ring.lineWidth = Theme.Line.emphasis
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ring.strokeColor = Theme.Palette.accent.cgColor
        }
        ring.path = path(outset: Theme.Space.pressRing)
        ring.opacity = 0
        layer.addSublayer(ring)

        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = path(outset: 0)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Theme.Motion.pressRing
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: nil)
        CATransaction.commit()
    }

    private func drawLabel(color: NSColor) {
        var fontSize = label.count > 2 ? Theme.FontSize.keyLongLabel : Theme.FontSize.keyLabel
        let attributes = { (size: CGFloat) -> [NSAttributedString.Key: Any] in
            [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        }
        // キーの幅に収まらないときは文字を小さくする
        let availableWidth = bounds.width - Theme.Space.keyLabelInset * 2
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
            fraction: isDimmed ? Theme.Palette.dimmedAlpha : 1
        )
    }

    private func drawHints(color: NSColor) {
        for (direction, hint) in hints {
            let text = NSAttributedString(string: hint, attributes: [
                .font: NSFont.systemFont(ofSize: Theme.FontSize.keyHint),
                .foregroundColor: color.withAlphaComponent(Theme.Palette.hintAlpha),
            ])
            let size = text.size()
            let inset = Theme.Space.keyHintInset
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
