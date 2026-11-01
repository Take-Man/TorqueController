import AppKit
import TorqueEngine

/// 候補の展開の動き。列ごとに少しずつ遅らせ、イーズアウトで中心から広がる。
enum RevealAnimation {
    static let duration: CFTimeInterval = 0.26
    static let columnDelay: CFTimeInterval = 0.025
    /// 動き始めの大きさ。
    static let startScale: CGFloat = 0.25

    /// 経過時間 elapsed での、列の進み具合(0 から 1)。
    static func progress(elapsed: CFTimeInterval, column: Int) -> CGFloat {
        let linear = (elapsed - Double(column) * columnDelay) / duration
        let clamped = min(1, max(0, linear))
        return CGFloat(1 - pow(1 - clamped, 3))
    }

    static func isFinished(elapsed: CFTimeInterval, columnCount: Int) -> Bool {
        elapsed >= duration + Double(columnCount) * columnDelay
    }
}

/// 候補の同心円の重ね表示。中心の円は入力欄のスコープを囲い、中は透けて見える。
final class CandidateOverlayView: NSView {
    static let backSymbol = "arrow.uturn.left"
    private static let font = NSFont.systemFont(ofSize: 15)
    private static let minColumnWidth: CGFloat = 36
    private static let maxColumnWidth: CGFloat = 140
    private static let cellPadding: CGFloat = 14

    var onRegionClicked: (@MainActor (CandidateLayout.Region) -> Void)?

    private var layout: CandidateLayout?
    private var session: ConversionSession?
    private var hovered: CandidateLayout.Region? {
        didSet {
            if hovered != oldValue { needsDisplay = true }
        }
    }
    private var pressed: CandidateLayout.Region?
    /// 展開を始めてからの経過時間。既定では展開し終えた状態。
    var revealElapsed = CFTimeInterval.greatestFiniteMagnitude
    private var revealStart: CFTimeInterval = 0
    private var revealLink: CADisplayLink?

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 表示する内容を変えて、配置を計算し直す。
    func update(session: ConversionSession, center: CGPoint, scopeRadius: CGFloat, animated: Bool = false) {
        self.session = session
        let columns = session.columns.indices.map { index in
            let visible = session.visibleCandidates(column: index)
            let textWidth = visible.map { Self.text($0.surface, color: .labelColor).size().width }.max() ?? 0
            return CandidateLayout.Column(
                width: min(Self.maxColumnWidth, max(Self.minColumnWidth, textWidth + Self.cellPadding)),
                rowCount: visible.count,
                hasNext: session.hasNextPage(column: index)
            )
        }
        layout = CandidateLayout(columns: columns, center: center, scopeRadius: scopeRadius, bounds: bounds)
        hovered = nil
        needsDisplay = true
        if animated {
            startReveal()
        } else {
            stopReveal()
        }
    }

    private func startReveal() {
        stopReveal()
        guard window != nil else { return }
        revealElapsed = 0
        revealStart = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(revealTick))
        link.add(to: .main, forMode: .common)
        revealLink = link
    }

    private func stopReveal() {
        revealLink?.invalidate()
        revealLink = nil
        revealElapsed = .greatestFiniteMagnitude
    }

    @objc private func revealTick() {
        revealElapsed = CACurrentMediaTime() - revealStart
        if RevealAnimation.isFinished(elapsed: revealElapsed, columnCount: layout?.columns.count ?? 0) {
            stopReveal()
        }
        // 動いている範囲は候補の配置の範囲に収まるので、そこだけ描き直す
        setNeedsDisplay(layout?.contentBounds ?? bounds)
    }

    private func reveal(column: Int) -> CGFloat {
        RevealAnimation.progress(elapsed: revealElapsed, column: column)
    }

    /// 中心から最終の位置へ向かう途中の位置。
    private func revealedPoint(_ rect: CGRect, center: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(x: center.x + (rect.midX - center.x) * progress, y: center.y + (rect.midY - center.y) * progress)
    }

    /// カーソルの位置の領域を調べてホバー表示を更新し、その領域を返す。
    func trackCursor(at point: CGPoint) -> CandidateLayout.Region? {
        hovered = layout?.region(at: point)
        return hovered
    }

    override func mouseDown(with event: NSEvent) {
        pressed = layout?.region(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let released = layout?.region(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil }
        if let released, released == pressed {
            onRegionClicked?(released)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let layout else { return }
        drawRings(layout)
        drawSpokes(layout)
        drawCenter(layout)
        drawBack(layout)
        for index in layout.columns.indices {
            let candidates = Array(session.visibleCandidates(column: index))
            for (row, candidate) in candidates.enumerated() {
                drawCell(layout.cellRect(column: index, row: row), column: index, region: .candidate(column: index, row: row)) { rect, color in
                    Self.draw(candidate.surface, in: rect, color: color)
                }
            }
            if let rect = layout.nextRect(column: index) {
                drawCell(rect, column: index, region: .next(column: index)) { rect, color in
                    Self.drawSymbol("chevron.down", in: rect, color: color, fraction: self.reveal(column: index))
                }
            }
        }
    }

    private func drawRings(_ layout: CandidateLayout) {
        for (column, radius) in layout.ringRadii.enumerated() {
            let progress = reveal(column: column)
            guard progress > 0 else { continue }
            NSColor.controlAccentColor.withAlphaComponent(0.25 * progress).setStroke()
            let angle = layout.arcAngle(column: column)
            let path = NSBezierPath()
            let current = layout.scopeRadius + (radius - layout.scopeRadius) * progress
            path.appendArc(withCenter: layout.center, radius: current, startAngle: angle, endAngle: -angle, clockwise: true)
            path.stroke()
        }
    }

    /// 中心の円の縁から各候補へ伸びる直線。候補の下に隠れるよう、候補の中心まで引く。
    private func drawSpokes(_ layout: CandidateLayout) {
        for column in layout.columns.indices {
            let progress = reveal(column: column)
            guard progress > 0 else { continue }
            NSColor.controlAccentColor.withAlphaComponent(0.25 * progress).setStroke()
            var rects = (0..<layout.columns[column].rowCount).map { layout.cellRect(column: column, row: $0) }
            if let next = layout.nextRect(column: column) {
                rects.append(next)
            }
            for rect in rects {
                let end = revealedPoint(rect, center: layout.center, progress: progress)
                let dx = end.x - layout.center.x
                let dy = end.y - layout.center.y
                let distance = hypot(dx, dy)
                guard distance > layout.scopeRadius else { continue }
                let path = NSBezierPath()
                path.move(to: NSPoint(
                    x: layout.center.x + dx / distance * layout.scopeRadius,
                    y: layout.center.y + dy / distance * layout.scopeRadius
                ))
                path.line(to: end)
                path.stroke()
            }
        }
    }

    /// 候補を、中心から最終の位置へ広がる途中の位置と大きさで描く。
    private func drawCell(_ rect: CGRect, column: Int, region: CandidateLayout.Region, content: (CGRect, NSColor) -> Void) {
        guard let layout else { return }
        let progress = reveal(column: column)
        guard progress > 0, let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        if progress < 1 {
            let position = revealedPoint(rect, center: layout.center, progress: progress)
            let scale = RevealAnimation.startScale + (1 - RevealAnimation.startScale) * progress
            context.setAlpha(progress)
            context.translateBy(x: position.x, y: position.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -rect.midX, y: -rect.midY)
        }
        let isHovered = hovered == region
        (isHovered ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        content(rect, isHovered ? .white : .labelColor)
        context.restoreGState()
    }

    private func drawCenter(_ layout: CandidateLayout) {
        let radius = layout.scopeRadius
        let circle = NSBezierPath(ovalIn: NSRect(x: layout.center.x - radius, y: layout.center.y - radius, width: radius * 2, height: radius * 2))
        NSColor.controlAccentColor.withAlphaComponent(hovered == .center ? 0.25 : 0.08).setFill()
        circle.fill()
        NSColor.controlAccentColor.setStroke()
        circle.lineWidth = 2
        circle.stroke()
    }

    /// 戻す領域。中心の円の左側に接する、90度の扇形。
    private func drawBack(_ layout: CandidateLayout) {
        let progress = reveal(column: 0)
        guard progress > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(progress)

        let inner = layout.scopeRadius + 2
        let outer = layout.scopeRadius + 2 + (CandidateLayout.backDepth - 2) * progress
        let path = NSBezierPath()
        path.appendArc(withCenter: layout.center, radius: outer, startAngle: 135, endAngle: 225)
        path.appendArc(withCenter: layout.center, radius: inner, startAngle: 225, endAngle: 135, clockwise: true)
        path.close()
        let isHovered = hovered == .back
        (isHovered ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let middle = (inner + outer) / 2
        let area = CGRect(x: layout.center.x - middle - 10, y: layout.center.y - 10, width: 20, height: 20)
        Self.drawSymbol(Self.backSymbol, in: area, color: isHovered ? .white : .secondaryLabelColor, fraction: progress)
    }

    private static func text(_ string: String, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    private static func draw(_ string: String, in rect: CGRect, color: NSColor) {
        let text = text(string, color: color)
        let height = text.size().height
        text.draw(in: CGRect(x: rect.minX + 3, y: rect.midY - height / 2, width: rect.width - 6, height: height))
    }

    /// NSImage はコンテキストの不透明度を無視するので、fraction で指定する。
    private static func drawSymbol(_ name: String, in rect: CGRect, color: NSColor, fraction: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        image.draw(
            in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: fraction
        )
    }
}
