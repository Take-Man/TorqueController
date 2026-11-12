import CoreGraphics
import Foundation
import Testing
@testable import TorqueController

private let interval: TimeInterval = 0.5
private let left: Int64 = 0
private let right: Int64 = 1
private let origin = CGPoint(x: 100, y: 100)

private func carrier(_ selected: CGEventFlags, locked: CGEventFlags = []) -> ModifierCarrier {
    var carrier = ModifierCarrier(doubleClickInterval: interval)
    carrier.configure(selected: selected, locked: locked)
    return carrier
}

// MARK: - クリックとドラッグ

@Test func clickCarriesFlagsAndReleasesAfterDoubleClickInterval() {
    var c = carrier(.maskShift)
    let r1 = c.press(button: left, at: origin, time: 0, isOwn: false)
    #expect(r1 == .init(flags: .maskShift, released: false))
    let r2 = c.release(button: left, at: origin, time: 0.1)
    #expect(r2 == .init(flags: .maskShift, released: false))
    // 間隔の間はまだ選んだまま
    #expect(c.deadline == 0.6)
    let r3 = c.expire(at: 0.59)
    #expect(!r3)
    #expect(c.selected == .maskShift)
    let r4 = c.expire(at: 0.6)
    #expect(r4)
    #expect(c.selected == [])
    #expect(!c.isActive)
}

@Test func nearRepressWithinIntervalIsCarried() {
    // ⌘+ダブルクリック
    var c = carrier(.maskCommand)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.05)
    let second = c.press(button: left, at: CGPoint(x: 103, y: 102), time: 0.3, isOwn: false)
    #expect(second == .init(flags: .maskCommand, released: false))
    // 押している間は時間で外さない
    #expect(c.deadline == nil)
    let r5 = c.release(button: left, at: origin, time: 0.35)
    #expect(r5.flags == .maskCommand)
    let r6 = c.expire(at: 0.85)
    #expect(r6)
}

@Test func farRepressReleasesFirst() {
    var c = carrier(.maskCommand)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.05)
    let far = c.press(button: left, at: CGPoint(x: 120, y: 100), time: 0.2, isOwn: false)
    #expect(far == .init(flags: [], released: true))
}

@Test func lateRepressReleasesFirst() {
    var c = carrier(.maskCommand)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.05)
    // タイマーより先にイベントが来ても、期限が過ぎていれば外す
    let r7 = c.press(button: left, at: origin, time: 0.6, isOwn: false)
    #expect(r7 == .init(flags: [], released: true))
}

@Test func dragKeepsFlagsUntilRelease() {
    var c = carrier(.maskAlternate)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    #expect(c.drag(button: left) == .maskAlternate)
    #expect(c.deadline == nil)
    // 長いドラッグでも、離すまでは外さない
    let r8 = c.expire(at: 10)
    #expect(!r8)
    let r9 = c.release(button: left, at: CGPoint(x: 300, y: 300), time: 10)
    #expect(r9.flags == .maskAlternate)
    let r10 = c.expire(at: 10.5)
    #expect(r10)
}

@Test func otherButtonsAreCarried() {
    var c = carrier(.maskControl)
    let r11 = c.press(button: right, at: origin, time: 0, isOwn: false)
    #expect(r11.flags == .maskControl)
    let r12 = c.release(button: right, at: origin, time: 0.1)
    #expect(r12.flags == .maskControl)
    let r13 = c.press(button: 2, at: origin, time: 0.2, isOwn: false)
    #expect(r13.flags == .maskControl)
}

@Test func flagsAreCombined() {
    var c = carrier([.maskCommand, .maskShift])
    let r14 = c.press(button: left, at: origin, time: 0, isOwn: false)
    #expect(r14.flags == [.maskCommand, .maskShift])
}

// MARK: - 対象外

@Test func ownOperationsAreNotCarriedNorConsumed() {
    var c = carrier(.maskShift)
    let r15 = c.press(button: left, at: origin, time: 0, isOwn: true)
    #expect(r15 == .init(flags: [], released: false))
    #expect(c.drag(button: left) == [])
    let r16 = c.release(button: left, at: origin, time: 0.1)
    #expect(r16 == .init(flags: [], released: false))
    #expect(c.deadline == nil)
    #expect(c.selected == .maskShift)
    let r17 = c.scroll(.wheel, time: 0.2, isOwn: true)
    #expect(r17 == .init(flags: [], released: false))
    #expect(c.deadline == nil)
    let r18 = c.expire(at: 100)
    #expect(!r18)
    #expect(c.selected == .maskShift)
}

@Test func ownClickDuringRepressWaitKeepsTheWait() {
    var c = carrier(.maskShift)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.1)
    _ = c.press(button: left, at: CGPoint(x: 500, y: 500), time: 0.2, isOwn: true)
    _ = c.release(button: left, at: CGPoint(x: 500, y: 500), time: 0.25)
    #expect(c.selected == .maskShift)
    let r19 = c.expire(at: 0.6)
    #expect(r19)
}

@Test func nothingIsCarriedWithoutSelection() {
    var c = ModifierCarrier(doubleClickInterval: interval)
    #expect(!c.isActive)
    let r20 = c.press(button: left, at: origin, time: 0, isOwn: false)
    #expect(r20 == .init(flags: [], released: false))
    let r21 = c.release(button: left, at: origin, time: 0.1)
    #expect(r21 == .init(flags: [], released: false))
    let r22 = c.scroll(.wheel, time: 0.2, isOwn: false)
    #expect(r22 == .init(flags: [], released: false))
    #expect(c.deadline == nil)
}

// MARK: - 固定

@Test func lockedFlagsStayAfterRelease() {
    var c = carrier([.maskCommand, .maskShift], locked: .maskCommand)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.1)
    let r23 = c.expire(at: 0.6)
    #expect(r23)
    #expect(c.selected == .maskCommand)
    // 固定だけが残ったら、時間で外すものはない
    let r24 = c.press(button: left, at: origin, time: 1, isOwn: false)
    #expect(r24.flags == .maskCommand)
    _ = c.release(button: left, at: origin, time: 1.1)
    #expect(c.deadline == nil)
    let r25 = c.scroll(.wheel, time: 2, isOwn: false)
    #expect(r25.flags == .maskCommand)
    #expect(c.deadline == nil)
}

@Test func configureDropsPendingRelease() {
    var c = carrier(.maskShift)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.1)
    c.configure(selected: [], locked: [])
    #expect(c.deadline == nil)
    let r26 = c.expire(at: 1)
    #expect(!r26)
}

// MARK: - スクロール

@Test func wheelReleasesAfterIdle() {
    var c = carrier(.maskControl)
    let r27 = c.scroll(.wheel, time: 0, isOwn: false)
    #expect(r27.flags == .maskControl)
    let r28 = c.scroll(.wheel, time: 0.2, isOwn: false)
    #expect(r28.flags == .maskControl)
    #expect(c.deadline == 0.2 + ModifierCarrier.scrollIdle)
    let r29 = c.expire(at: 0.4)
    #expect(!r29)
    let r30 = c.expire(at: 0.5)
    #expect(r30)
    let r31 = c.scroll(.wheel, time: 0.6, isOwn: false)
    #expect(r31.flags == [])
}

@Test func trackpadScrollWaitsForMomentumEnd() {
    var c = carrier(.maskControl)
    let r32 = c.scroll(.touching, time: 0, isOwn: false)
    #expect(r32.flags == .maskControl)
    // 指が触れている間は時間で外さない
    #expect(c.deadline == nil)
    let r33 = c.expire(at: 5)
    #expect(!r33)
    let r34 = c.scroll(.lifted, time: 5, isOwn: false)
    #expect(r34.flags == .maskControl)
    let r35 = c.scroll(.momentum, time: 5.02, isOwn: false)
    #expect(r35.flags == .maskControl)
    let r36 = c.scroll(.momentum, time: 5.2, isOwn: false)
    #expect(r36.flags == .maskControl)
    // 慣性の終わりのイベントにも乗せ、そこで外す
    let r37 = c.scroll(.momentumEnded, time: 5.3, isOwn: false)
    #expect(r37 == .init(flags: .maskControl, released: true))
    #expect(c.selected == [])
}

@Test func trackpadScrollWithoutMomentumReleasesAfterIdle() {
    var c = carrier(.maskControl)
    _ = c.scroll(.touching, time: 0, isOwn: false)
    _ = c.scroll(.lifted, time: 1, isOwn: false)
    let r38 = c.expire(at: 1 + ModifierCarrier.scrollIdle)
    #expect(r38)
}

@Test func clickAfterScrollIsAnotherOperation() {
    var c = carrier(.maskControl)
    _ = c.scroll(.wheel, time: 0, isOwn: false)
    let r39 = c.press(button: left, at: origin, time: 0.1, isOwn: false)
    #expect(r39 == .init(flags: [], released: true))
}

@Test func scrollAfterClickIsAnotherOperation() {
    var c = carrier(.maskShift)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    _ = c.release(button: left, at: origin, time: 0.1)
    let r40 = c.scroll(.wheel, time: 0.2, isOwn: false)
    #expect(r40 == .init(flags: [], released: true))
}

@Test func scrollWhileDraggingBelongsToTheDrag() {
    var c = carrier(.maskAlternate)
    _ = c.press(button: left, at: origin, time: 0, isOwn: false)
    let r41 = c.scroll(.wheel, time: 0.1, isOwn: false)
    #expect(r41.flags == .maskAlternate)
    #expect(c.deadline == nil)
}

@Test func scrollPhasesAreClassified() {
    #expect(ModifierCarrier.Scroll(scrollPhase: 0, momentumPhase: 0) == .wheel)
    #expect(ModifierCarrier.Scroll(scrollPhase: 1, momentumPhase: 0) == .touching)
    #expect(ModifierCarrier.Scroll(scrollPhase: 2, momentumPhase: 0) == .touching)
    #expect(ModifierCarrier.Scroll(scrollPhase: 128, momentumPhase: 0) == .touching)
    #expect(ModifierCarrier.Scroll(scrollPhase: 4, momentumPhase: 0) == .lifted)
    #expect(ModifierCarrier.Scroll(scrollPhase: 8, momentumPhase: 0) == .lifted)
    #expect(ModifierCarrier.Scroll(scrollPhase: 0, momentumPhase: 1) == .momentum)
    #expect(ModifierCarrier.Scroll(scrollPhase: 0, momentumPhase: 2) == .momentum)
    #expect(ModifierCarrier.Scroll(scrollPhase: 0, momentumPhase: 3) == .momentumEnded)
}
