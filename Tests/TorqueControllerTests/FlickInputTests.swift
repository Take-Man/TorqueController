import AppKit
import Testing
@testable import TorqueController

@Test func cyclesDakutenAndSmallKana() {
    var composition = Composition()
    composition.appendPending("は")
    composition.cycleLast()
    #expect(composition.pending == "ば")
    composition.cycleLast()
    #expect(composition.pending == "ぱ")
    composition.cycleLast()
    #expect(composition.pending == "は")

    composition.clear()
    composition.appendPending("つ")
    composition.cycleLast()
    #expect(composition.pending == "っ")
    composition.cycleLast()
    #expect(composition.pending == "づ")
    composition.cycleLast()
    #expect(composition.pending == "つ")
}

@Test func cycleOnlyTouchesLastCharacter() {
    var composition = Composition()
    composition.appendPending("はは")
    composition.cycleLast()
    #expect(composition.pending == "はば")
}

@Test func cycleIgnoresCharactersWithoutVariants() {
    var composition = Composition()
    composition.cycleLast()
    #expect(composition.pending == "")
    composition.appendPending("ん")
    composition.cycleLast()
    #expect(composition.pending == "ん")
}

@Test func shiftOnceReleasesAfterOneCharacter() {
    let once = LatchState.off.pressed(isDoubleClick: false)
    #expect(once == .once)
    #expect(once.afterInput == .off)
}

@Test func shiftDoubleClickLocksUntilPressedAgain() {
    let locked = LatchState.off.pressed(isDoubleClick: false).pressed(isDoubleClick: true)
    #expect(locked == .locked)
    #expect(locked.afterInput == .locked)
    #expect(locked.pressed(isDoubleClick: false) == .off)
}

@Test func shiftSlowSecondPressTurnsOff() {
    #expect(LatchState.once.pressed(isDoubleClick: false) == .off)
}

@Test func uppercasedKeysInputCapitals() {
    guard case .flick(let abc) = InputMode.latin.grid[1].uppercased else {
        Issue.record("abc のキーがフリックのキーではない")
        return
    }
    #expect(abc.label == "ABC")
    #expect(abc.character(in: nil) == "A")
    #expect(abc.character(in: .up) == "C")
}

@Test func deleteRemovesOneCharacter() {
    var composition = Composition()
    composition.deleteLast()
    #expect(composition.isEmpty)
    composition.appendPending("あい")
    composition.deleteLast()
    #expect(composition.pending == "あ")
}

@Test func confirmedTextStaysBeforePending() {
    var composition = Composition()
    composition.appendPending("あ")
    composition.appendConfirmed("1")
    #expect(composition.confirmed == "あ1")
    #expect(composition.pending == "")
    composition.appendPending("か")
    #expect(composition.text == "あ1か")
}

@Test func cycleDoesNotTouchConfirmedText() {
    var composition = Composition()
    composition.appendConfirmed("は")
    composition.cycleLast()
    #expect(composition.text == "は")
}

@Test func deleteRemovesPendingThenConfirmed() {
    var composition = Composition()
    composition.appendConfirmed("亜")
    composition.appendPending("い")
    composition.deleteLast()
    #expect(composition.text == "亜")
    composition.deleteLast()
    #expect(composition.isEmpty)
}

@Test func conversionKeepsConvertedAsConfirmed() {
    var composition = Composition()
    composition.appendConfirmed("前")
    composition.appendPending("きょうは")
    composition.applyConversion(converted: "今日", remaining: "は")
    #expect(composition.confirmed == "前今日")
    #expect(composition.pending == "は")
}

@Test func onlyLongLeftDragClears() {
    #expect(DeleteGesture.isClear(offset: CGVector(dx: -30, dy: 0)))
    #expect(DeleteGesture.isClear(offset: CGVector(dx: -80, dy: 40)))
    #expect(!DeleteGesture.isClear(offset: CGVector(dx: -29, dy: 0)))
    #expect(!DeleteGesture.isClear(offset: CGVector(dx: 80, dy: 0)))
}

@Test func clearEmptiesWholeField() {
    var composition = Composition()
    composition.appendConfirmed("確定")
    composition.appendPending("みかくてい")
    composition.clear()
    #expect(composition.isEmpty)
}

@Test func directionWorksFarOutsideTheGuide() {
    let from = { (dx: CGFloat, dy: CGFloat) in
        FlickDirection.from(offset: CGVector(dx: dx, dy: dy), deadZone: FlickGuideView.innerRadius)
    }
    #expect(from(-3000, 200) == .left)
    #expect(from(3000, 200) == .right)
    #expect(from(100, 3000) == .up)
    #expect(from(100, -3000) == .down)
}

@Test func directionFollowsLargerAxis() {
    let from = { (dx: CGFloat, dy: CGFloat) in
        FlickDirection.from(offset: CGVector(dx: dx, dy: dy), deadZone: 24)
    }
    #expect(from(0, 0) == nil)
    #expect(from(10, 10) == nil)
    #expect(from(-40, 5) == .left)
    #expect(from(40, -5) == .right)
    #expect(from(5, 40) == .up)
    #expect(from(-5, -40) == .down)
}

@Test func kanaKeyMapsDirectionsToVowels() throws {
    guard case .flick(let ka) = InputMode.kana.grid[1] else {
        Issue.record("か行のキーがフリックのキーではない")
        return
    }
    #expect(ka.character(in: nil) == "か")
    #expect(ka.character(in: .left) == "き")
    #expect(ka.character(in: .up) == "く")
    #expect(ka.character(in: .right) == "け")
    #expect(ka.character(in: .down) == "こ")
}

@Test func missingDirectionHasNoCharacter() {
    guard case .flick(let wa) = InputMode.kana.grid[10] else {
        Issue.record("わ行のキーがフリックのキーではない")
        return
    }
    #expect(wa.character(in: .left) == "を")
    #expect(wa.character(in: .down) == nil)
}

@Test func everyModeHasTwelveKeys() {
    for mode in InputMode.allCases {
        #expect(mode.grid.count == 12)
    }
}

@Test func chunksRespectLimitAndKeepCharactersWhole() {
    #expect(TextSender.chunks(of: "", maxUnits: 20).isEmpty)
    #expect(TextSender.chunks(of: "あいう", maxUnits: 2) == ["あい", "う"])
    // 絵文字は UTF-16 で2単位なので、途中で分けない
    #expect(TextSender.chunks(of: "あ😀", maxUnits: 2) == ["あ", "😀"])
    let long = String(repeating: "あ", count: 45)
    let chunks = TextSender.chunks(of: long, maxUnits: 20)
    #expect(chunks.allSatisfy { $0.utf16.count <= 20 })
    #expect(chunks.joined() == long)
}

@MainActor @Test(arguments: PanelSettings.scaleChoices)
func fieldDoesNotCollapseUntilPanelWidthAtAnyScale(scale: CGFloat) {
    let view = CompositionView(frame: .zero)
    view.maxFieldWidth = 280
    // パネルの幅に収まるあいだ(全角18ptで14文字)は畳まない
    for count in [1, 7, 14] {
        view.pendingText = String(repeating: "あ", count: count)
        let size = view.fittingSize()
        // 倍率をかけたパネルと同じく、frame と bounds の比を変える
        view.frame = NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        view.setBoundsSize(size)
        #expect(!view.overflows)
        #expect(size.height == CompositionView.collapsedPanelHeight)
    }
    view.pendingText = String(repeating: "あ", count: 40)
    #expect(view.overflows)
}

private func keyViews(in panel: NSPanel) -> [KeyView] {
    panel.contentView?.subviews.compactMap { $0 as? KeyView } ?? []
}

@MainActor @Test func selectionDoesNotWaitForGuideReveal() throws {
    _ = NSApplication.shared
    let panel = FlickPanel(origin: .zero, converter: nil, learningURL: URL(fileURLWithPath: "/dev/null"))
    panel.show()
    defer { panel.hide() }
    let key = try #require(keyViews(in: panel.panel).first { $0.label == "か" })
    key.onBegin?(.zero)
    let guide = try #require(panel.guidePanel.contentView as? FlickGuideView)
    #expect(guide.revealProgress == 0)
    let offset = CGVector(dx: 0, dy: 40)
    key.onDrag?(offset)
    #expect(guide.direction == .up)
    key.onEnd?(offset, true)
    #expect(guide.revealProgress < 1)
    #expect(panel.fieldText == "く")
}

@MainActor @Test func qwertyShiftShowsSelectedState() throws {
    let panel = QwertyPanel(origin: .zero)
    let shift = try #require(keyViews(in: panel.panel).first { $0.symbolName == "shift" })
    #expect(!shift.isSelected)
    shift.onEnd?(.zero, true)
    #expect(shift.isSelected)
    #expect(!shift.isLocked)
}

@Test func easeOutStaysInRange() {
    #expect(RevealAnimation.easeOut(-1) == 0)
    #expect(RevealAnimation.easeOut(0.5) > 0.5)
    #expect(RevealAnimation.easeOut(2) == 1)
}
