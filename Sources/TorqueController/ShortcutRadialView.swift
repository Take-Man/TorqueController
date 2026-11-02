import AppKit

/// 修飾キーからのドラッグで出す、階層型の同心円。押した位置を中心に描く。
final class ShortcutRadialView: RadialGuideView {
    var radial: ShortcutRadial? {
        didSet { needsDisplay = true }
    }
    var selection = ShortcutRadial.Selection.center {
        didSet {
            if selection != oldValue { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let radial else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        var selected: [ShortcutRadial.Node] = []
        if case .path(let path) = selection {
            selected = path
        }

        drawRevealed(center: center, innerRadius: ShortcutRadial.centerRadius, outerRadius: radial.drawnRadius) {
            drawCancel(center: center, ringWidth: radial.ringWidth)
            // 選んでいる区画の輪郭線が隣に消されないよう、最後に内側から順に描く
            let nodes = radial.visibleNodes(for: selection)
            for node in nodes where !selected.contains(node) {
                drawNode(node, center: center, ringWidth: radial.ringWidth, isActive: false)
            }
            for node in selected {
                drawNode(node, center: center, ringWidth: radial.ringWidth, isActive: true)
            }
            if let last = selected.last {
                let labels = selected.map { labelPoint($0, center: center, ringWidth: radial.ringWidth) }
                drawSpoke(center: center, innerRadius: ShortcutRadial.centerRadius, to: labelPoint(last, center: center, ringWidth: radial.ringWidth), passing: Array(labels.dropLast()))
            }
        }
        drawCenter(radial.origin.symbol, center: center, radius: ShortcutRadial.centerRadius, isSelected: selection == .center, fontSize: Theme.FontSize.shortcutRadial)
    }

    /// 位置(0 から 270)を、描画の角度(右が0度、反時計回り)に直す。
    private func angle(_ position: CGFloat) -> CGFloat {
        135 - position
    }

    private func drawNode(_ node: ShortcutRadial.Node, center: NSPoint, ringWidth: CGFloat, isActive: Bool) {
        let inner = ShortcutRadial.centerRadius + ringWidth * CGFloat(node.ring)
        let outer = inner + ringWidth
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer, startAngle: angle(node.start), endAngle: angle(node.end), clockwise: true)
        path.appendArc(withCenter: center, radius: inner, startAngle: angle(node.end), endAngle: angle(node.start))
        path.close()
        drawSector(path, state: isActive ? .active : .idle)
        let color = isActive ? Theme.Palette.accent : Theme.Palette.text
        drawLabel(node.label, at: labelPoint(node, center: center, ringWidth: ringWidth), color: color, fontSize: Theme.FontSize.shortcutRadial)
    }

    private func labelPoint(_ node: ShortcutRadial.Node, center: NSPoint, ringWidth: CGFloat) -> NSPoint {
        let middle = angle((node.start + node.end) / 2) * .pi / 180
        let radius = ShortcutRadial.centerRadius + ringWidth * (CGFloat(node.ring) + 0.5)
        return NSPoint(x: center.x + cos(middle) * radius, y: center.y + sin(middle) * radius)
    }

    /// キャンセルは色を付けない灰色の区画にする。
    private func drawCancel(center: NSPoint, ringWidth: CGFloat) {
        let inner = ShortcutRadial.centerRadius
        let outer = inner + ringWidth / 2
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer, startAngle: 135, endAngle: 225)
        path.appendArc(withCenter: center, radius: inner, startAngle: 225, endAngle: 135, clockwise: true)
        path.close()
        let isActive = selection == .cancel
        drawSector(path, state: isActive ? .neutralActive : .neutral)
        let color = isActive ? Theme.Palette.text : Theme.Palette.secondaryText
        drawLabel("×", at: NSPoint(x: center.x - (inner + outer) / 2, y: center.y), color: color, fontSize: Theme.FontSize.shortcutRadial)
    }
}
