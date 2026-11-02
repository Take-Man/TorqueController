import AppKit

/// クリックしても入力先のフォーカスを奪わないパネル。
final class FloatingPanel: NSPanel {
    /// 右クリックされたとき。全てのパネルで共通。
    static var onRightClick: (@MainActor (NSEvent, NSView) -> Void)?
    /// 背景の波紋。キーボードの3つのパネルだけが持つ。
    private(set) var rippleView: RippleView?

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

    /// 土台を置いた直後、キーを置く前に呼ぶ。波紋はキーの後ろ、ぼかしの上に入る。
    func installRipple() {
        guard let background = contentView as? PanelBackgroundView else { return }
        let view = RippleView(frame: background.bounds)
        background.content = view
        rippleView = view
    }

    /// 右クリックはキーに届けず、ここで受ける。左ボタンでキーを押している間は何もしない。
    /// 波紋はキーの処理の後に出すので、キーの反応を待たせない。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown {
            if NSEvent.pressedMouseButtons & 1 == 0, let contentView {
                Self.onRightClick?(event, contentView)
            }
            return
        }
        let rippleOrigin = event.type == .leftMouseDown ? rippleOrigin(of: event) : nil
        super.sendEvent(event)
        if let rippleOrigin {
            rippleView?.ripple(at: rippleOrigin)
        }
    }

    /// 押した先が波紋を出すキーなら、波紋の座標での位置を返す。持ち手や余白では nil。
    private func rippleOrigin(of event: NSEvent) -> NSPoint? {
        guard let rippleView, let contentView, let superview = contentView.superview else { return nil }
        let target = contentView.hitTest(superview.convert(event.locationInWindow, from: nil))
        guard (target as? RippleSource)?.firesRipple == true else { return nil }
        return rippleView.convert(event.locationInWindow, from: nil)
    }

    /// 倍率をかけて置く。中身は logicalSize の座標のまま描くので、倍率はビューの bounds で与える。
    func place(origin: NSPoint, logicalSize: NSSize, scale: CGFloat) {
        setFrame(NSRect(x: origin.x, y: origin.y, width: logicalSize.width * scale, height: logicalSize.height * scale), display: false)
        contentView?.setBoundsSize(logicalSize)
        contentView?.needsDisplay = true
        rippleView?.scale = scale
    }
}

/// ぼかしを見せる形。角丸の四角から cutout を除いた範囲。
struct PanelBackgroundShape: Equatable, Sendable {
    /// 下の角が見えないよう、下へ伸ばす長さ。
    var bottomOverhang: CGFloat = 0
    /// 別のパネルと重なる範囲。重なりが濃く見えないよう、ぼかしを見せない。
    var cutout: CGRect?

    /// 今の色で、この形を rect に塗る。
    func fill(_ rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let radius = Theme.Radius.panel
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: -bottomOverhang, width: rect.width, height: rect.height + bottomOverhang),
            xRadius: radius,
            yRadius: radius
        ).addClip()
        let path = NSBezierPath(rect: rect)
        if let cutout {
            path.append(NSBezierPath(roundedRect: cutout, xRadius: radius, yRadius: radius))
            path.windingRule = .evenOdd
        }
        path.fill()
    }

    /// NSVisualEffectView のマスク。不透明な部分だけにぼかしを見せる。
    func maskImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            fill(rect)
            return true
        }
    }
}

/// パネルの土台。半透明のぼかしを敷き、ドラッグでパネルが動かないようにする。
final class PanelBackgroundView: NSView {
    /// ぼかしはクリックを受けない。
    private final class EffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    /// ぼかしの上に重ねる色。マスクはぼかしだけに効くので、同じ形を自分で塗る。
    private final class VeilView: NSView {
        var shape = PanelBackgroundShape() {
            didSet { needsDisplay = true }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            Theme.Palette.panelVeil.setFill()
            shape.fill(bounds)
        }
    }

    private let effectView = EffectView()
    private let veilView = VeilView()
    private var maskSize = NSSize.zero

    var shape = PanelBackgroundShape() {
        didSet {
            veilView.shape = shape
            fitContent(force: true)
        }
    }
    /// 土台いっぱいに広げる中身。
    var content: NSView? {
        didSet {
            if let content {
                addSubview(content)
            }
            fitContent()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        effectView.material = Theme.panelMaterial
        effectView.blendingMode = .behindWindow
        // パネルはキーウィンドウにならないので、ウィンドウの状態に従うとぼかしが消える
        effectView.state = .active
        addSubview(effectView)
        addSubview(veilView)
        fitContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitContent()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        fitContent()
    }

    /// 倍率は bounds で与えるので、中身は bounds に合わせる。
    private func fitContent(force: Bool = false) {
        effectView.frame = bounds
        veilView.frame = bounds
        content?.frame = bounds
        if force || maskSize != bounds.size {
            maskSize = bounds.size
            effectView.maskImage = shape.maskImage(size: bounds.size)
            // 影はウィンドウの中身の形から作るので、形が変わったら作り直す
            window?.invalidateShadow()
        }
    }
}

/// パネルの余白に置く、パネルを掴むための持ち手。6個の点を描く。
final class GripView: NSView {
    private static let dotDiameter: CGFloat = 3
    private static let dotSpacing = Theme.Space.gripDotSpacing

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
        Theme.Palette.tertiaryText.setFill()
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
