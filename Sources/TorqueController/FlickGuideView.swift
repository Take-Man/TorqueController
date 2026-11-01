import AppKit

/// フリックのガイド。押した位置を中心に、上下左右に区分した同心円を描く。
final class FlickGuideView: NSView {
    static let innerRadius: CGFloat = 20
    static let outerRadius: CGFloat = ShortcutRadial.baseRadius
    private static let labelRadius: CGFloat = 42

    var characters: FlickCharacters? {
        didSet { needsDisplay = true }
    }
    var direction: FlickDirection? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let characters else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        for sector in FlickDirection.allCases {
            let path = NSBezierPath()
            let middle = Self.angle(of: sector)
            path.appendArc(withCenter: center, radius: Self.outerRadius, startAngle: middle - 45, endAngle: middle + 45)
            path.appendArc(withCenter: center, radius: Self.innerRadius, startAngle: middle + 45, endAngle: middle - 45, clockwise: true)
            path.close()
            fillColor(isActive: sector == direction).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()

            if let character = characters.outer[sector] {
                let radians = middle * .pi / 180
                let point = NSPoint(x: center.x + cos(radians) * Self.labelRadius, y: center.y + sin(radians) * Self.labelRadius)
                draw(character, at: point, isActive: sector == direction)
            }
        }

        let inner = NSBezierPath(ovalIn: NSRect(x: center.x - Self.innerRadius, y: center.y - Self.innerRadius, width: Self.innerRadius * 2, height: Self.innerRadius * 2))
        fillColor(isActive: direction == nil).setFill()
        inner.fill()
        NSColor.separatorColor.setStroke()
        inner.stroke()
        draw(characters.center, at: center, isActive: direction == nil)
    }

    private func fillColor(isActive: Bool) -> NSColor {
        isActive ? .controlAccentColor : .windowBackgroundColor
    }

    private func draw(_ string: String, at point: NSPoint, isActive: Bool) {
        let text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: isActive ? NSColor.white : NSColor.labelColor,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    private static func angle(of direction: FlickDirection) -> CGFloat {
        switch direction {
        case .right: 0
        case .up: 90
        case .left: 180
        case .down: 270
        }
    }
}
