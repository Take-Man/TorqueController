import AppKit

/// 押した位置を中心に出す同心円(フリックのガイド、修飾キーの同心円)の共通の描き方。
/// 開くときは外周が中心から広がる。選択は移動量だけで決まるので、動きを待たない。
class RadialGuideView: NSView {
    enum SectorState {
        case idle, active
        /// 何も入力しない区画。色を付けない。
        case neutral, neutralActive
    }

    private var revealLink: CADisplayLink?
    private var revealStart: CFTimeInterval = 0
    /// 開く動きの進み具合(0 から 1)。
    var revealProgress: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    /// ウィンドウを出した後に呼ぶ。
    func startReveal() {
        revealLink?.invalidate()
        revealProgress = 0
        revealStart = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(revealTick))
        link.add(to: .main, forMode: .common)
        revealLink = link
    }

    @objc private func revealTick() {
        let linear = (CACurrentMediaTime() - revealStart) / Theme.Motion.guideReveal
        revealProgress = RevealAnimation.easeOut(linear)
        // 影はウィンドウの中身の形から作るので、広がりに合わせて作り直す
        window?.invalidateShadow()
        if linear >= 1 {
            revealLink?.invalidate()
            revealLink = nil
        }
    }

    /// 中心の円の縁の半径から outerRadius まで広がる途中の大きさで、中心の周りを描く。
    func drawRevealed(center: NSPoint, innerRadius: CGFloat, outerRadius: CGFloat, _ body: () -> Void) {
        guard revealProgress > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if revealProgress < 1 {
            let start = innerRadius / outerRadius
            let scale = start + (1 - start) * revealProgress
            context.setAlpha(revealProgress)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)
        }
        body()
    }

    func drawSector(_ path: NSBezierPath, state: SectorState) {
        Theme.Palette.guideBase.setFill()
        path.fill()
        switch state {
        case .idle:
            Theme.Palette.separator.setStroke()
            path.lineWidth = Theme.Line.thin
        case .active:
            Theme.drawActive(path)
            return
        case .neutral:
            Theme.Palette.neutralTint.setFill()
            path.fill()
            Theme.Palette.separator.setStroke()
            path.lineWidth = Theme.Line.thin
        case .neutralActive:
            Theme.Palette.neutralTint.setFill()
            path.fill()
            Theme.Palette.neutralStroke.setStroke()
            path.lineWidth = Theme.Line.emphasis
        }
        path.stroke()
    }

    /// 中心の円。押したキーの文字を、輪と淡い塗りで囲む。下地は広がる途中の区画を隠す。
    func drawCenter(_ label: String, center: NSPoint, radius: CGFloat, isSelected: Bool, fontSize: CGFloat) {
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        Theme.Palette.guideBase.setFill()
        circle.fill()
        Theme.drawActive(circle)
        drawLabel(label, at: center, color: isSelected ? Theme.Palette.accent : Theme.Palette.text, fontSize: fontSize)
    }

    /// 中心の円の縁から、選んでいる文字の手前まで伸ばす直線。途中の文字(passing)の上は描かない。
    func drawSpoke(center: NSPoint, innerRadius: CGFloat, to point: NSPoint, passing: [NSPoint] = []) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        let end = distance - Theme.Space.spokeToLabel
        guard distance > 0, end > innerRadius else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + dx / distance * innerRadius, y: center.y + dy / distance * innerRadius))
        path.line(to: NSPoint(x: center.x + dx / distance * end, y: center.y + dy / distance * end))
        path.lineWidth = Theme.Line.thin
        Theme.Palette.accent.setStroke()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let clip = NSBezierPath(rect: bounds)
        let gap = Theme.Space.spokeToLabel
        for label in passing {
            clip.appendOval(in: NSRect(x: label.x - gap, y: label.y - gap, width: gap * 2, height: gap * 2))
        }
        clip.windingRule = .evenOdd
        clip.addClip()
        path.stroke()
    }

    func drawLabel(_ string: String, at point: NSPoint, color: NSColor, fontSize: CGFloat) {
        let text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }
}
