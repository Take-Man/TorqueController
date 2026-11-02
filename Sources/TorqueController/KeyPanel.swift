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

/// 1行に畳んだ入力欄の、見える範囲。隠れた側には省略記号を出す。
struct CollapsedLine: Equatable {
    /// 文字列の中で、見える範囲の左端の位置。
    let start: CGFloat
    let hidesLeading: Bool
    let hidesTrailing: Bool

    /// focus があれば、その位置が見えるようにする(変換中の未確定の先頭)。なければ末尾を見せる。
    init(textWidth: CGFloat, availableWidth: CGFloat, ellipsisWidth: CGFloat, focus: CGFloat?) {
        let tailStart = textWidth - (availableWidth - ellipsisWidth)
        if textWidth <= availableWidth {
            (start, hidesLeading, hidesTrailing) = (0, false, false)
        } else if let focus, focus < tailStart {
            (start, hidesLeading, hidesTrailing) = (focus, focus > 0, true)
        } else {
            (start, hidesLeading, hidesTrailing) = (tailStart, true, false)
        }
    }
}

/// キーボードの上に出す入力欄。背景はキーボードと地続きにする。確定済みの文字列の後ろに未確定のかなを並べる。
/// 長いときは1行に畳み、上端のマークをクリックすると折り返して全てを表示する。
final class CompositionView: NSView {
    /// 入力欄の周りの、キーボードと同じ背景の幅。
    static let margin: CGFloat = 8
    /// 下の余白はキーボードの上端に重ねて、背景をつなげる。
    static let overlap: CGFloat = 8
    private static let collapsedFieldHeight: CGFloat = 40
    /// 1行のときのパネルの高さ。
    static let collapsedPanelHeight = collapsedFieldHeight + margin + overlap
    private static let textInset: CGFloat = 8
    /// 開閉のマークを置く、上端の帯の高さ。
    private static let toggleHeight: CGFloat = 18
    private static let font = NSFont.systemFont(ofSize: 18)
    private static let ellipsis = "…"

    var confirmedText = "" {
        didSet { needsDisplay = true }
    }
    var pendingText = "" {
        didSet { needsDisplay = true }
    }
    /// 変換中は未確定の部分に下線を引く。
    var underlinesPending = false {
        didSet { needsDisplay = true }
    }
    var isExpanded = false {
        didSet { needsDisplay = true }
    }
    /// 入力欄の幅の上限。パネルの幅で決まる。これを超えると畳む。
    var maxFieldWidth: CGFloat = 0
    var onClick: (@MainActor () -> Void)?
    /// 開閉のマークのクリックを伝える。
    var onExpandChange: (@MainActor (Bool) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 文字列がパネルの幅に収まらず、畳むか開くかを選ぶとき true。
    /// 倍率をかけると bounds の幅に誤差が出るので、bounds ではなく上限の幅で判断する。
    var overflows: Bool {
        Self.width(fullText) > maxTextWidth
    }

    private var maxTextWidth: CGFloat {
        maxFieldWidth - Self.textInset * 2
    }

    /// 文字列に合わせた、パネルの大きさ。入力欄の幅は maxFieldWidth まで。
    func fittingSize() -> NSSize {
        let fieldWidth = min(maxFieldWidth, Self.width(fullText) + Self.textInset * 2)
        var fieldHeight = Self.collapsedFieldHeight
        if isExpanded, overflows {
            let layout = TextLayout(string: attributedText, width: fieldWidth - Self.textInset * 2)
            fieldHeight = max(fieldHeight, layout.usedHeight + Self.textInset * 2)
        }
        let topMargin = overflows ? Self.toggleHeight : Self.margin
        return NSSize(width: fieldWidth + Self.margin * 2, height: fieldHeight + topMargin + Self.overlap)
    }

    /// 未確定の先頭 count 文字が表示されている範囲。この欄の座標で返す。
    func pendingRect(count: Int) -> CGRect {
        let confirmedLength = (confirmedText as NSString).length
        let scopeLength = (String(pendingText.prefix(count)) as NSString).length
        let field = fieldRect
        if showsWrappedText {
            let layout = TextLayout(string: attributedText, width: textRect.width)
            let rect = layout.boundingRect(location: confirmedLength, length: scopeLength)
            return CGRect(x: textRect.minX + rect.minX, y: textRect.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let line = collapsedLine
        let clip = collapsedClipRect(line)
        let start = textRect.minX + (line.hidesLeading ? Self.ellipsisWidth : 0) - line.start + Self.width(confirmedText)
        let end = start + Self.width(String(pendingText.prefix(count)))
        let minX = max(clip.minX, start)
        let maxX = min(clip.maxX, end)
        let height = Self.font.ascender - Self.font.descender
        return CGRect(x: minX, y: field.midY - height / 2, width: max(0, maxX - minX), height: height)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if overflows, point.y >= fieldRect.maxY {
            onExpandChange?(!isExpanded)
        } else {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 下の角はキーボードの中に隠れるので、丸めない
        NSColor.windowBackgroundColor.setFill()
        let outer = NSRect(x: 0, y: -12, width: bounds.width, height: bounds.height + 12)
        NSBezierPath(roundedRect: outer, xRadius: 12, yRadius: 12).fill()

        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: fieldRect, xRadius: 8, yRadius: 8).fill()

        if showsWrappedText {
            attributedText.draw(with: textRect, options: [.usesLineFragmentOrigin])
        } else {
            drawCollapsed()
        }
        if overflows {
            drawToggle()
        }
    }

    private func drawCollapsed() {
        let line = collapsedLine
        let clip = collapsedClipRect(line)
        let string = attributedText
        let height = string.size().height
        let y = fieldRect.midY - height / 2

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        string.draw(at: NSPoint(x: clip.minX - line.start, y: y))
        NSGraphicsContext.restoreGraphicsState()

        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        if line.hidesLeading {
            NSAttributedString(string: Self.ellipsis, attributes: attributes).draw(at: NSPoint(x: textRect.minX, y: y))
        }
        if line.hidesTrailing {
            NSAttributedString(string: Self.ellipsis, attributes: attributes).draw(at: NSPoint(x: textRect.maxX - Self.ellipsisWidth, y: y))
        }
    }

    /// 上端の帯に出す、開閉のマーク。
    private func drawToggle() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        guard let image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        image.draw(in: NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - Self.toggleHeight / 2 - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    private var fullText: String { confirmedText + pendingText }
    private var showsWrappedText: Bool { isExpanded && overflows }

    private var fieldRect: NSRect {
        NSRect(
            x: Self.margin,
            y: Self.overlap,
            width: bounds.width - Self.margin * 2,
            height: bounds.height - Self.overlap - (overflows ? Self.toggleHeight : Self.margin)
        )
    }

    private var textRect: NSRect {
        fieldRect.insetBy(dx: Self.textInset, dy: Self.textInset)
    }

    private var collapsedLine: CollapsedLine {
        CollapsedLine(
            textWidth: Self.width(fullText),
            availableWidth: maxTextWidth,
            ellipsisWidth: Self.ellipsisWidth,
            focus: underlinesPending ? Self.width(confirmedText) : nil
        )
    }

    /// 文字列を見せる範囲。省略記号の分を除く。
    private func collapsedClipRect(_ line: CollapsedLine) -> NSRect {
        var rect = NSRect(x: textRect.minX, y: fieldRect.minY, width: textRect.width, height: fieldRect.height)
        if line.hidesLeading {
            rect.origin.x += Self.ellipsisWidth
            rect.size.width -= Self.ellipsisWidth
        }
        if line.hidesTrailing {
            rect.size.width -= Self.ellipsisWidth
        }
        return rect
    }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let string = NSMutableAttributedString(string: confirmedText, attributes: attributes)
        var pendingAttributes = attributes
        if underlinesPending {
            pendingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        string.append(NSAttributedString(string: pendingText, attributes: pendingAttributes))
        return string
    }

    private static var ellipsisWidth: CGFloat { width(ellipsis) }

    private static func width(_ string: String) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    /// 折り返した文字列の配置を調べる。座標は文字列の左上が原点で、y は下が正。
    private struct TextLayout {
        private let manager = NSLayoutManager()
        private let container: NSTextContainer
        private let storage: NSTextStorage

        init(string: NSAttributedString, width: CGFloat) {
            storage = NSTextStorage(attributedString: string)
            container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
        }

        var usedHeight: CGFloat {
            ceil(manager.usedRect(for: container).height)
        }

        func boundingRect(location: Int, length: Int) -> CGRect {
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: location, length: length), actualCharacterRange: nil)
            return manager.boundingRect(forGlyphRange: glyphs, in: container)
        }
    }
}
