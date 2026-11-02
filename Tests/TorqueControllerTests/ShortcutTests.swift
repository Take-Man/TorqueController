import CoreGraphics
import Testing
@testable import TorqueController

private func shortcuts(_ texts: String...) -> [Shortcut] {
    texts.compactMap(Shortcut.init)
}

@Test func parsesModifiersInAnyOrder() throws {
    let first = try #require(Shortcut("command+shift+4"))
    let second = try #require(Shortcut("Shift+CMD+4"))
    #expect(first == second)
    #expect(first.modifiers == [.command, .shift])
    #expect(first.key == "4")
}

@Test func rejectsInvalidShortcuts() {
    #expect(Shortcut("c") == nil)
    #expect(Shortcut("command+") == nil)
    #expect(Shortcut("hyper+c") == nil)
    #expect(Shortcut("command+xy") == nil)
}

@Test func defaultsAreAllValid() {
    #expect(ShortcutStore.parse(Shortcut.defaults).count == Shortcut.defaults.count)
}

@Test func anglesAreProportionalToShortcutCount() throws {
    // 設計の例: C, V, Z, shift+3, shift+4 は 1:1:1:2 で、3 と 4 が shift の範囲を半分ずつ占める
    let radial = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c", "command+v", "command+z", "command+shift+3", "command+shift+4"))
    #expect(radial.roots.map(\.label) == ["C", "V", "Z", "⇧"])
    #expect(radial.roots.map { $0.end - $0.start } == [54, 54, 54, 108])
    let shift = radial.roots[3]
    #expect(shift.children.map(\.label) == ["3", "4"])
    #expect(shift.children[0].start == shift.start)
    #expect(shift.children[1].end == shift.end)
    #expect(shift.children[0].end - shift.children[0].start == 54)
}

@Test func combinationsAreEquivalentFromEitherModifier() {
    let list = shortcuts("command+shift+3")
    let fromCommand = ShortcutRadial(origin: .command, shortcuts: list)
    let fromShift = ShortcutRadial(origin: .shift, shortcuts: list)
    #expect(fromCommand.roots.map(\.label) == ["⇧"])
    #expect(fromShift.roots.map(\.label) == ["⌘"])
    #expect(fromCommand.roots[0].children[0].kind == fromShift.roots[0].children[0].kind)
}

@Test func unrelatedCombinationsAreNotShown() {
    let radial = ShortcutRadial(origin: .option, shortcuts: shortcuts("command+c"))
    #expect(radial.roots.isEmpty)
}

@Test func selectionFollowsCenterCancelAndRings() throws {
    let radial = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c", "command+shift+3", "command+shift+4"))
    #expect(radial.selection(offset: CGVector(dx: 5, dy: 5)) == .center)
    #expect(radial.selection(offset: CGVector(dx: -60, dy: 0)) == .cancel)
    #expect(radial.selection(offset: CGVector(dx: -60, dy: 40)) == .cancel)

    // 270度の先頭の90度が C、残りが shift
    let onC = radial.selection(offset: CGVector(dx: 0, dy: 50))
    guard case .path(let cPath) = onC else {
        Issue.record("項目を選べていない")
        return
    }
    #expect(cPath.map(\.label) == ["C"])

    // shift の範囲の内側の列
    guard case .path(let shiftPath) = radial.selection(offset: CGVector(dx: 50, dy: -10)) else {
        Issue.record("項目を選べていない")
        return
    }
    #expect(shiftPath.map(\.label) == ["⇧"])

    // さらに外側の列で、3 か 4 を選ぶ
    guard case .path(let outerPath) = radial.selection(offset: CGVector(dx: 110, dy: -20)) else {
        Issue.record("項目を選べていない")
        return
    }
    #expect(outerPath.count == 2)
    #expect(outerPath.first?.label == "⇧")
    if case .key(let shortcut)? = outerPath.last?.kind {
        #expect(shortcut.modifiers == [.command, .shift])
    } else {
        Issue.record("外側の列の項目がショートカットではない")
    }
}

@Test func radiusGrowsOneAndHalfTimesForTwoRings() {
    let one = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c"))
    let two = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c", "command+shift+3"))
    #expect(one.maxRadius == ShortcutRadial.baseRadius)
    #expect(two.maxRadius == ShortcutRadial.baseRadius * 1.5)
    #expect(two.ringWidth < one.ringWidth)
}

@Test(arguments: [
    CGVector(dx: 5000, dy: -800),
    CGVector(dx: 0, dy: 5000),
    CGVector(dx: 5000, dy: 100),
    CGVector(dx: 300, dy: -4000),
])
func farOutsideTheCircleStillSelectsByDirection(offset: CGVector) {
    let radial = ShortcutRadial(origin: .command, shortcuts: ShortcutStore.parse(Shortcut.defaults))
    guard case .path(let path) = radial.selection(offset: offset), let last = path.last else {
        Issue.record("項目を選べていない")
        return
    }
    // 外側の段まで進むので、修飾キーの上で止まらず必ずショートカットに決まる
    guard case .key = last.kind else {
        Issue.record("ショートカットに決まっていない")
        return
    }
}

@Test func farLeftOfTheCircleStillCancels() {
    let radial = ShortcutRadial(origin: .command, shortcuts: ShortcutStore.parse(Shortcut.defaults))
    #expect(radial.selection(offset: CGVector(dx: -5000, dy: 100)) == .cancel)
}

@Test func keyOnFirstRingStaysSelectedFartherOut() {
    let radial = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c"))
    guard case .path(let path) = radial.selection(offset: CGVector(dx: 0, dy: 300)) else {
        Issue.record("項目を選べていない")
        return
    }
    #expect(path.map(\.label) == ["C"])
}

@Test func visibleNodesExpandOnlySelectedModifier() {
    let radial = ShortcutRadial(origin: .command, shortcuts: shortcuts("command+c", "command+shift+3"))
    #expect(radial.visibleNodes(for: .center).count == 2)
    #expect(radial.visibleNodes(for: radial.selection(offset: CGVector(dx: 50, dy: -30))).count == 3)
}

@Test func qwertyRowsContainRequiredKeys() {
    let keys = QwertyKey.rows.flatMap(\.keys)
    #expect(keys.contains(.delete))
    #expect(keys.contains(.enter))
    #expect(keys.contains(.space))
    #expect(keys.contains(.tab))
    #expect(keys.contains(.shift))
    #expect(keys.contains(.character(base: "4", shifted: "$")))
    #expect(keys.contains(.character(base: "z", shifted: "Z")))
}

@Test func qwertyHasFourRowsWithShiftBesideZAndSpaceAfterSlash() {
    #expect(QwertyKey.rows.count == 4)
    let keys = QwertyKey.rows[3].keys
    #expect(keys.first == .shift)
    #expect(keys[1] == .character(base: "z", shifted: "Z"))
    #expect(keys.last == .space)
    #expect(keys[keys.count - 2] == .character(base: "/", shifted: "?"))
    #expect(QwertyKey.rows[2].keys.first == .tab)
    #expect(QwertyKey.rows[2].keys[1] == .character(base: "a", shifted: "A"))
}

@MainActor @Test func qwertyShiftAppliesOnceThenLocksLikeCapsLock() {
    let qwerty = QwertyPanel(origin: .zero)
    #expect(qwerty.displayed(base: "a", shifted: "A") == "a")
    qwerty.update(modifiers: [.shift], highlighted: [])
    #expect(qwerty.displayed(base: "a", shifted: "A") == "A")
    #expect(qwerty.displayed(base: "4", shifted: "$") == "$")
    qwerty.update(modifiers: [.command, .shift], highlighted: ["4"])
    #expect(qwerty.displayed(base: "4", shifted: "$") == "4")
}

@Test func dPadRespondsOnlyInCrossBlocks() {
    let at = { (dx: CGFloat, dy: CGFloat) in
        ArrowDirection.at(offset: CGVector(dx: dx, dy: dy), radius: 45)
    }
    #expect(at(0, 30) == .up)
    #expect(at(0, -30) == .down)
    #expect(at(-30, 0) == .left)
    #expect(at(30, 0) == .right)
    // 中央のブロック
    #expect(at(0, 0) == nil)
    #expect(at(10, 10) == nil)
    // 四隅のブロック
    #expect(at(25, 25) == nil)
    #expect(at(-25, 25) == nil)
    // 円の外
    #expect(at(0, 50) == nil)
}

@Test func keyCodesComeFromCurrentLayout() throws {
    // 英字の z と数字の 4 は、どのキー配列にもある
    #expect(KeyboardLayout.keyCode(for: "z") != nil)
    #expect(KeyboardLayout.keyCode(for: "4") != nil)
    #expect(KeyboardLayout.keyCode(for: "あ") == nil)
}

@Test func modifierFlagsAndLeftKeyCodes() {
    #expect(Set<Modifier>([.command, .shift]).flags == [.maskCommand, .maskShift])
    #expect(Modifier.allCases.map(\.leftKeyCode) == [55, 56, 58, 59])
}

@Test func modifierShowsQwertyAndEmptySelectionHidesIt() {
    var visibility = QwertyVisibility()
    visibility.modifierSelected()
    #expect(visibility.isVisible)
    visibility.selectionEmptied()
    #expect(!visibility.isVisible)
}

@Test func toggleHidesQwertyWhileModifierIsSelected() {
    var visibility = QwertyVisibility()
    visibility.modifierSelected()
    visibility.toggled()
    #expect(!visibility.isVisible)
    // 選択が空になっても勝手には出ない
    visibility.selectionEmptied()
    #expect(!visibility.isVisible)
    // 別の修飾キーを選ぶとまた出る
    visibility.modifierSelected()
    #expect(visibility.isVisible)
}

@Test func manuallyShownQwertyStaysAfterSelectionEmpties() {
    var visibility = QwertyVisibility()
    visibility.toggled()
    visibility.modifierSelected()
    visibility.selectionEmptied()
    #expect(visibility.isVisible)
}
