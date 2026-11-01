import CoreGraphics
import Testing
@testable import TorqueController

@Test func cyclesDakutenAndSmallKana() {
    var composition = Composition()
    composition.append("は")
    composition.cycleLast()
    #expect(composition.text == "ば")
    composition.cycleLast()
    #expect(composition.text == "ぱ")
    composition.cycleLast()
    #expect(composition.text == "は")

    composition.clear()
    composition.append("つ")
    composition.cycleLast()
    #expect(composition.text == "っ")
    composition.cycleLast()
    #expect(composition.text == "づ")
    composition.cycleLast()
    #expect(composition.text == "つ")
}

@Test func cycleOnlyTouchesLastCharacter() {
    var composition = Composition()
    composition.append("はは")
    composition.cycleLast()
    #expect(composition.text == "はば")
}

@Test func cycleIgnoresCharactersWithoutVariants() {
    var composition = Composition()
    composition.cycleLast()
    #expect(composition.text == "")
    composition.append("ん")
    composition.cycleLast()
    #expect(composition.text == "ん")
}

@Test func shiftOnceReleasesAfterOneCharacter() {
    let once = ShiftState.off.pressed(isDoubleClick: false)
    #expect(once == .once)
    #expect(once.afterInput == .off)
}

@Test func shiftDoubleClickLocksUntilPressedAgain() {
    let locked = ShiftState.off.pressed(isDoubleClick: false).pressed(isDoubleClick: true)
    #expect(locked == .locked)
    #expect(locked.afterInput == .locked)
    #expect(locked.pressed(isDoubleClick: false) == .off)
}

@Test func shiftSlowSecondPressTurnsOff() {
    #expect(ShiftState.once.pressed(isDoubleClick: false) == .off)
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
    composition.append("あい")
    composition.deleteLast()
    #expect(composition.text == "あ")
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
