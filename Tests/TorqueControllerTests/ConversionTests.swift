import CoreGraphics
import Foundation
import Testing
@testable import TorqueController
@testable import TorqueEngine

private func candidate(_ surface: String) -> Candidate {
    Candidate(surface: surface, dictionaryCost: 0, connectionCost: 0, learningBonus: 0)
}

/// 読みの先頭2文字を1列にする、単純な候補の作り方。
private func session(_ reading: String, candidateCount: Int = 2) -> ConversionSession {
    ConversionSession(reading: reading) { remaining in
        let head = String(remaining.prefix(2))
        let candidates = (0..<candidateCount).map { candidate("\(head)\($0)") }
        return [CandidateColumn(reading: head, candidates: candidates)]
    }
}

@Test func selectingAdvancesToRemainingReading() {
    var conversion = session("あいうえ")
    #expect(conversion.remaining == "あいうえ")
    conversion.select(column: 0, candidate: candidate("亜以"))
    #expect(conversion.convertedText == "亜以")
    #expect(conversion.remaining == "うえ")
    #expect(conversion.columns[0].reading == "うえ")
    #expect(!conversion.isFinished)
    conversion.select(column: 0, candidate: candidate("植"))
    #expect(conversion.isFinished)
    #expect(conversion.commitText == "亜以植")
}

@Test func commitKeepsUnconvertedReadingAsKana() {
    var conversion = session("あいうえ")
    conversion.select(column: 0, candidate: candidate("亜以"))
    #expect(conversion.commitText == "亜以うえ")
}

@Test func undoRestoresPreviousSelection() {
    var conversion = session("あいうえ")
    let undoneNothing = conversion.undo()
    #expect(!undoneNothing)
    conversion.select(column: 0, candidate: candidate("亜以"))
    let undone = conversion.undo()
    #expect(undone)
    #expect(conversion.remaining == "あいうえ")
    #expect(conversion.selections.isEmpty)
    #expect(conversion.columns[0].reading == "あい")
}

@Test func firstColumnPagesShowFiveAndWrapAround() {
    var conversion = session("あい", candidateCount: 7)
    #expect(conversion.hasNextPage(column: 0))
    #expect(conversion.visibleCandidates(column: 0).map(\.surface).first == "あい0")
    #expect(conversion.visibleCandidates(column: 0).count == 5)
    conversion.nextPage(column: 0)
    #expect(conversion.visibleCandidates(column: 0).map(\.surface) == ["あい5", "あい6"])
    conversion.nextPage(column: 0)
    #expect(conversion.visibleCandidates(column: 0).map(\.surface).first == "あい0")
}

@Test func shortColumnHasNoNextPage() {
    #expect(!session("あい", candidateCount: 5).hasNextPage(column: 0))
}

private func makeLayout() -> CandidateLayout {
    CandidateLayout(
        columns: [
            .init(width: 100, rowCount: 5, hasNext: true),
            .init(width: 60, rowCount: 2, hasNext: false),
            .init(width: 60, rowCount: 7, hasNext: false),
        ],
        center: CGPoint(x: 300, y: 400),
        scopeRadius: 40,
        bounds: CGRect(x: 0, y: 0, width: 1400, height: 900)
    )
}

@Test func outerColumnsHaveOneMoreCandidate() {
    #expect(ConversionSession.pageSize(column: 0) == 5)
    #expect(ConversionSession.pageSize(column: 1) == 6)
    #expect(ConversionSession.pageSize(column: 2) == 7)
}

@Test func innerColumnIsOnSmallerRing() {
    let layout = makeLayout()
    #expect(layout.columns.count == 3)
    #expect(layout.ringRadii[0] > layout.scopeRadius)
    #expect(layout.ringRadii[1] > layout.ringRadii[0])
    #expect(layout.ringRadii[2] > layout.ringRadii[1])
}

@Test func rowsAreEvenlySpacedAndSymmetric() {
    let layout = makeLayout()
    let step = CandidateLayout.cellHeight + CandidateLayout.rowGap
    let heights = (0..<5).map { layout.cellRect(column: 0, row: $0).midY }
    for (upper, lower) in zip(heights, heights.dropFirst()) {
        #expect(upper - lower == step)
    }
    // 1列目は「次へ」を合わせて6行なので、中心の高さをはさむ
    let next = layout.nextRect(column: 0)?.midY ?? 0
    #expect(heights[0] - layout.center.y == layout.center.y - next)
    #expect(heights[0] - layout.center.y == step * 2.5)
}

@Test func neighborColumnsAreHalfRowApartAndEveryOtherColumnAligns() {
    let layout = makeLayout()
    let step = CandidateLayout.cellHeight + CandidateLayout.rowGap
    let first = layout.cellRect(column: 0, row: 0).midY
    #expect(layout.cellRect(column: 1, row: 0).midY - first == step / 2)
    #expect(layout.cellRect(column: 2, row: 0).midY - first == step)
    #expect(layout.cellRect(column: 2, row: 1).midY == first)
}

@Test func fanDoesNotOpenBeyondHalfAngle() {
    let layout = CandidateLayout(
        columns: [.init(width: 36, rowCount: 5, hasNext: true)],
        center: CGPoint(x: 300, y: 400),
        scopeRadius: 26,
        bounds: CGRect(x: 0, y: 0, width: 1400, height: 900)
    )
    #expect(layout.arcAngle(column: 0) <= 30)
    #expect(layout.arcAngle(column: 0) > 28)
}

@Test func cellsSitOnTheirRing() {
    let layout = makeLayout()
    let rect = layout.cellRect(column: 0, row: 1)
    let distance = hypot(rect.midX - layout.center.x, rect.midY - layout.center.y)
    #expect(abs(distance - layout.ringRadii[0]) < 0.001)
}

@Test func cellsDoNotOverlap() {
    let layout = makeLayout()
    var rects = (0..<5).map { layout.cellRect(column: 0, row: $0) }
    rects += (0..<2).map { layout.cellRect(column: 1, row: $0) }
    rects += (0..<7).map { layout.cellRect(column: 2, row: $0) }
    rects.append(layout.nextRect(column: 0) ?? .zero)
    for (index, rect) in rects.enumerated() {
        for other in rects[(index + 1)...] {
            #expect(!rect.intersects(other))
        }
    }
}

@Test func cellsDoNotTouchTheCenterCircle() {
    let layout = makeLayout()
    for row in 0..<5 {
        let rect = layout.cellRect(column: 0, row: row)
        let nearestX = min(max(layout.center.x, rect.minX), rect.maxX)
        let nearestY = min(max(layout.center.y, rect.minY), rect.maxY)
        #expect(hypot(nearestX - layout.center.x, nearestY - layout.center.y) >= layout.scopeRadius)
    }
}

@Test func regionsFollowLayout() {
    let layout = makeLayout()
    #expect(layout.region(at: layout.center) == .center)
    let top = layout.cellRect(column: 0, row: 0)
    #expect(layout.region(at: CGPoint(x: top.midX, y: top.midY)) == .candidate(column: 0, row: 0))
    let next = layout.nextRect(column: 0) ?? .zero
    #expect(layout.region(at: CGPoint(x: next.midX, y: next.midY)) == .next(column: 0))
    #expect(layout.nextRect(column: 1) == nil)
}

@Test func backRegionIsLeftNinetyDegreeSector() {
    let layout = makeLayout()
    let radius = layout.scopeRadius + CandidateLayout.backDepth / 2
    func point(angle: CGFloat) -> CGPoint {
        CGPoint(x: layout.center.x + cos(angle * .pi / 180) * radius, y: layout.center.y + sin(angle * .pi / 180) * radius)
    }
    #expect(layout.region(at: point(angle: 180)) == .back)
    #expect(layout.region(at: point(angle: 140)) == .back)
    #expect(layout.region(at: point(angle: 220)) == .back)
    #expect(layout.region(at: point(angle: 130)) != .back)
    #expect(layout.region(at: point(angle: 230)) != .back)
    // 扇形より外は何もない
    #expect(layout.region(at: CGPoint(x: layout.center.x - layout.scopeRadius - CandidateLayout.backDepth - 5, y: layout.center.y)) == nil)
}

@Test func columnsThatDoNotFitAreDropped() {
    let layout = CandidateLayout(
        columns: [.init(width: 100, rowCount: 5, hasNext: false), .init(width: 100, rowCount: 6, hasNext: false)],
        center: CGPoint(x: 150, y: 150),
        scopeRadius: 40,
        bounds: CGRect(x: 0, y: 0, width: 340, height: 300)
    )
    #expect(layout.columns.count == 1)
}

@Test func shortTextIsNotCollapsed() {
    let line = CollapsedLine(textWidth: 100, availableWidth: 200, ellipsisWidth: 10, focus: nil)
    #expect(line == CollapsedLine(textWidth: 100, availableWidth: 200, ellipsisWidth: 10, focus: 50))
    #expect(line.start == 0)
    #expect(!line.hidesLeading)
    #expect(!line.hidesTrailing)
}

@Test func longTextShowsTailWithoutFocus() {
    let line = CollapsedLine(textWidth: 500, availableWidth: 200, ellipsisWidth: 10, focus: nil)
    #expect(line.hidesLeading)
    #expect(!line.hidesTrailing)
    #expect(line.start == 310)
}

@Test func focusInMiddleHidesBothSides() {
    let line = CollapsedLine(textWidth: 500, availableWidth: 200, ellipsisWidth: 10, focus: 100)
    #expect(line.start == 100)
    #expect(line.hidesLeading)
    #expect(line.hidesTrailing)
}

@Test func focusAtStartHidesOnlyTrailing() {
    let line = CollapsedLine(textWidth: 500, availableWidth: 200, ellipsisWidth: 10, focus: 0)
    #expect(line.start == 0)
    #expect(!line.hidesLeading)
    #expect(line.hidesTrailing)
}

@Test func focusNearEndShowsTail() {
    let line = CollapsedLine(textWidth: 500, availableWidth: 200, ellipsisWidth: 10, focus: 450)
    #expect(line.start == 310)
    #expect(line.hidesLeading)
    #expect(!line.hidesTrailing)
}

@Test func revealStartsAtZeroAndEndsAtOne() {
    #expect(RevealAnimation.progress(elapsed: 0, column: 0) == 0)
    #expect(RevealAnimation.progress(elapsed: RevealAnimation.duration, column: 0) == 1)
    #expect(RevealAnimation.progress(elapsed: .greatestFiniteMagnitude, column: 5) == 1)
}

@Test func revealEasesOutAndDelaysOuterColumns() {
    let half = RevealAnimation.duration / 2
    #expect(RevealAnimation.progress(elapsed: half, column: 0) > 0.5)
    #expect(RevealAnimation.progress(elapsed: half, column: 1) < RevealAnimation.progress(elapsed: half, column: 0))
}

@Test func revealFinishesAfterLastColumn() {
    let columns = 6
    let end = RevealAnimation.duration + Double(columns) * RevealAnimation.columnDelay
    #expect(!RevealAnimation.isFinished(elapsed: end - 0.01, columnCount: columns))
    #expect(RevealAnimation.isFinished(elapsed: end, columnCount: columns))
    #expect(RevealAnimation.progress(elapsed: end, column: columns - 1) == 1)
}

@Test func contentBoundsContainEverything() {
    let layout = makeLayout()
    #expect(layout.contentBounds.contains(layout.cellRect(column: 2, row: 6)))
    #expect(layout.contentBounds.contains(layout.nextRect(column: 0) ?? .zero))
    #expect(layout.contentBounds.contains(CGPoint(x: layout.center.x - layout.scopeRadius - CandidateLayout.backDepth, y: layout.center.y)))
}
