import AppKit

/// 修飾キーからのドラッグで出す、階層型の同心円。押した位置を中心に描く。
final class ShortcutRadialView: NSView {
    var radial: ShortcutRadial? {
        didSet { needsDisplay = true }
    }
    var selection = ShortcutRadial.Selection.center {
        didSet {
            if selection != oldValue { needsDisplay = true }
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let radial else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        var selected: [ShortcutRadial.Node] = []
        if case .path(let path) = selection {
            selected = path
        }

        drawCancel(center: center)
        for node in radial.visibleNodes(for: selection) {
            drawNode(node, center: center, isActive: selected.contains(node))
        }

        let radius = ShortcutRadial.centerRadius
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        (selection == .center ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.stroke()
        drawLabel(radial.origin.symbol, at: center, isActive: selection == .center)
    }

    /// 位置(0 から 270)を、描画の角度(右が0度、反時計回り)に直す。
    private func angle(_ position: CGFloat) -> CGFloat {
        135 - position
    }

    private func drawNode(_ node: ShortcutRadial.Node, center: NSPoint, isActive: Bool) {
        let inner = ShortcutRadial.centerRadius + ShortcutRadial.ringWidth * CGFloat(node.ring)
        let outer = inner + ShortcutRadial.ringWidth
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer, startAngle: angle(node.start), endAngle: angle(node.end), clockwise: true)
        path.appendArc(withCenter: center, radius: inner, startAngle: angle(node.end), endAngle: angle(node.start))
        path.close()
        (isActive ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let middle = angle((node.start + node.end) / 2) * .pi / 180
        let radius = (inner + outer) / 2
        drawLabel(node.label, at: NSPoint(x: center.x + cos(middle) * radius, y: center.y + sin(middle) * radius), isActive: isActive)
    }

    private func drawCancel(center: NSPoint) {
        let inner = ShortcutRadial.centerRadius
        let outer = inner + ShortcutRadial.ringWidth / 2
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer, startAngle: 135, endAngle: 225)
        path.appendArc(withCenter: center, radius: inner, startAngle: 225, endAngle: 135, clockwise: true)
        path.close()
        let isActive = selection == .cancel
        (isActive ? NSColor.controlAccentColor : NSColor.windowBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        drawLabel("×", at: NSPoint(x: center.x - (inner + outer) / 2, y: center.y), isActive: isActive)
    }

    private func drawLabel(_ string: String, at point: NSPoint, isActive: Bool) {
        let text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: isActive ? NSColor.white : NSColor.labelColor,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }
}
