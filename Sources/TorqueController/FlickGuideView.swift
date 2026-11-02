import AppKit

/// フリックのガイド。押した位置を中心に、上下左右に区分した同心円を描く。
final class FlickGuideView: RadialGuideView {
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

        drawRevealed(center: center, innerRadius: Self.innerRadius, outerRadius: Self.outerRadius) {
            // 選んでいる区画の輪郭線が隣に消されないよう、最後に描く
            for sector in FlickDirection.allCases.sorted(by: { a, _ in a != direction }) {
                let isActive = sector == direction
                let character = characters.outer[sector]
                drawSector(sectorPath(sector, center: center), state: isActive ? (character == nil ? .neutralActive : .active) : .idle)
                if let character {
                    let color = isActive ? Theme.Palette.accent : Theme.Palette.text
                    drawLabel(character, at: labelPoint(sector, center: center), color: color, fontSize: Theme.FontSize.flickGuide)
                }
            }
            if let direction, characters.outer[direction] != nil {
                drawSpoke(center: center, innerRadius: Self.innerRadius, to: labelPoint(direction, center: center))
            }
        }
        drawCenter(characters.center, center: center, radius: Self.innerRadius, isSelected: direction == nil, fontSize: Theme.FontSize.flickGuide)
    }

    private func sectorPath(_ sector: FlickDirection, center: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        let middle = Self.angle(of: sector)
        path.appendArc(withCenter: center, radius: Self.outerRadius, startAngle: middle - 45, endAngle: middle + 45)
        path.appendArc(withCenter: center, radius: Self.innerRadius, startAngle: middle + 45, endAngle: middle - 45, clockwise: true)
        path.close()
        return path
    }

    private func labelPoint(_ sector: FlickDirection, center: NSPoint) -> NSPoint {
        let radians = Self.angle(of: sector) * .pi / 180
        return NSPoint(x: center.x + cos(radians) * Self.labelRadius, y: center.y + sin(radians) * Self.labelRadius)
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
