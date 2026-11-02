import CoreGraphics

/// 候補の同心円の配置。中心は変換のスコープを囲う円で、読みの長い列ほど内側の円に置く。
/// 行の間隔は全ての列で同じで、横の位置だけで各列の円の上に乗せる。外側の列ほど行が1つ増えるので全体は扇形になり、
/// 隣の列とは高さが半行ずれる。座標は表示領域の中の座標。
struct CandidateLayout {
    enum Region: Equatable {
        case candidate(column: Int, row: Int)
        case next(column: Int)
        case center
        case back
    }

    struct Column {
        let width: CGFloat
        let rowCount: Int
        let hasNext: Bool
    }

    static let cellHeight: CGFloat = 28
    static let backDepth: CGFloat = 26
    /// 上下の候補の間隔。同心円の線が見える程度の隙間を残す。
    static let rowGap: CGFloat = 6
    private static let rowStep = cellHeight + rowGap
    private static let cellSpacing: CGFloat = 3
    private static let centerSpacing: CGFloat = 8
    private static let searchStep: CGFloat = 2
    /// 扇形の半分の角度の上限。これより開かないよう、円の半径を大きくする。
    private static let maxHalfAngle: CGFloat = 30

    let center: CGPoint
    let scopeRadius: CGFloat
    /// 左右反転した配置か。候補は中心の左へ並び、戻す領域は右に来る。
    let isMirrored: Bool
    /// 画面に収まらず、隠れた候補や端に寄せた候補があるか。
    private(set) var isClipped = false
    private(set) var columns: [Column] = []
    private(set) var ringRadii: [CGFloat] = []
    private var cells: [[CGRect]] = []
    private var nextCells: [CGRect?] = []

    /// 候補は bounds の中に収める。置く場所がなくなった列から外側は表示しない。
    init(columns: [Column], center: CGPoint, scopeRadius: CGFloat, bounds: CGRect, isMirrored: Bool = false) {
        self.center = center
        self.scopeRadius = scopeRadius
        self.isMirrored = isMirrored

        var occupied: [CGRect] = []
        var radius: CGFloat = 0
        let maxRadius = hypot(bounds.width, bounds.height)

        placing: for (index, column) in columns.enumerated() {
            let rowCount = Self.rowCount(column: index)
            radius = max(radius, Self.maxRowOffset(column: index) / sin(Self.maxHalfAngle * .pi / 180))
            while true {
                radius += Self.searchStep
                guard radius <= maxRadius else {
                    isClipped = true
                    break placing
                }
                let exactRows = (0..<rowCount).map { cellRect(row: $0, rowCount: rowCount, radius: radius, width: column.width) }
                let rows = exactRows.map { Self.clamped($0, into: bounds) }
                let used = Array(rows.prefix(column.rowCount)) + (column.hasNext ? [rows[rowCount - 1]] : [])
                let spaced = used.map { $0.insetBy(dx: -Self.cellSpacing, dy: -Self.cellSpacing) }
                let isClear = !spaced.contains { rect in
                    occupied.contains { $0.intersects(rect) } || touchesCenter(rect)
                }
                if isClear {
                    let isCellClipped = (0..<rowCount).contains { row in
                        let isUsed = row < column.rowCount || (column.hasNext && row == rowCount - 1)
                        return isUsed && !bounds.contains(exactRows[row])
                    }
                    isClipped = isClipped || isCellClipped
                    self.columns.append(column)
                    ringRadii.append(radius)
                    cells.append(Array(rows.prefix(column.rowCount)))
                    nextCells.append(column.hasNext ? rows[rowCount - 1] : nil)
                    occupied += used
                    break
                }
            }
        }
    }

    /// 表示するものが全て入る範囲。
    var contentBounds: CGRect {
        let reach = scopeRadius + Self.backDepth
        var result = CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)
        for rect in cells.joined() {
            result = result.union(rect)
        }
        for rect in nextCells.compactMap({ $0 }) {
            result = result.union(rect)
        }
        return result.insetBy(dx: -4, dy: -4)
    }

    func cellRect(column: Int, row: Int) -> CGRect {
        cells[column][row]
    }

    func nextRect(column: Int) -> CGRect? {
        nextCells[column]
    }

    /// 列の円の上で、最上段(最下段)までの角度(度)。
    func arcAngle(column: Int) -> CGFloat {
        asin(min(1, Self.maxRowOffset(column: column) / ringRadii[column])) * 180 / .pi
    }

    func region(at point: CGPoint) -> Region? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        if distance <= scopeRadius { return .center }
        let outward = isMirrored ? dx : -dx
        if distance <= scopeRadius + Self.backDepth, outward > 0, abs(dy) <= outward { return .back }

        for column in cells.indices {
            for row in cells[column].indices where cells[column][row].contains(point) {
                return .candidate(column: column, row: row)
            }
            if nextCells[column]?.contains(point) == true {
                return .next(column: column)
            }
        }
        return nil
    }

    /// 候補と「次へ」を合わせた行の数。「次へ」は常に最下段に置く。
    private static func rowCount(column: Int) -> Int {
        ConversionSession.pageSize(column: column) + 1
    }

    /// 最上段の、中心からの高さ。
    static func maxRowOffset(column: Int) -> CGFloat {
        rowOffset(row: 0, rowCount: rowCount(column: column))
    }

    private static func rowOffset(row: Int, rowCount: Int) -> CGFloat {
        (CGFloat(rowCount - 1) / 2 - CGFloat(row)) * rowStep
    }

    private func cellRect(row: Int, rowCount: Int, radius: CGFloat, width: CGFloat) -> CGRect {
        let offset = Self.rowOffset(row: row, rowCount: rowCount)
        let distance = (radius * radius - offset * offset).squareRoot()
        let x = isMirrored ? center.x - distance : center.x + distance
        return CGRect(
            x: x - width / 2,
            y: center.y + offset - Self.cellHeight / 2,
            width: width,
            height: Self.cellHeight
        )
    }

    private func touchesCenter(_ rect: CGRect) -> Bool {
        let nearestX = min(max(center.x, rect.minX), rect.maxX)
        let nearestY = min(max(center.y, rect.minY), rect.maxY)
        return hypot(nearestX - center.x, nearestY - center.y) < scopeRadius + Self.centerSpacing
    }

    private static func clamped(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return result
    }
}
