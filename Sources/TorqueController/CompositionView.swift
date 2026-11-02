import AppKit

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

/// フリックパネルの上に出す入力欄。背景はパネルと地続きにする。確定済みの文字列の後ろに未確定のかなを並べる。
/// 長いときは1行に畳み、上端のマークをクリックすると折り返して全てを表示する。
final class CompositionView: NSView {
    /// 入力欄の周りの、パネルと同じ背景の幅。
    static let margin: CGFloat = 8
    /// 下の余白はパネルの上端に重ねて、背景をつなげる。
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
        // 下の角はパネルの中に隠れるので、丸めない
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
