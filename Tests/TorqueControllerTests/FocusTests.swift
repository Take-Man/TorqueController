import AppKit
import Testing
@testable import TorqueController

private func classify(_ role: String?, _ subrole: String? = nil, settable: Bool = false, secure: Bool = false) -> FocusKind {
    FocusKind.classify(role: role, subrole: subrole, hasSettableSelection: settable, isSecureInput: secure)
}

@Test func textRolesAreTextInput() {
    #expect(classify("AXTextField") == .text)
    #expect(classify("AXTextArea") == .text)
    #expect(classify("AXComboBox") == .text)
    #expect(classify("AXGroup", settable: true) == .text)
    #expect(classify("AXButton") == .none)
    // Chrome はチェックボックスでも選択範囲を設定可能と答える
    #expect(classify("AXCheckBox", settable: true) == .none)
    #expect(classify("AXStaticText") == .transient)
    #expect(classify("AXStaticText", secure: true) == .secure)
    #expect(classify(nil) == .none)
}

@Test func secureFieldOrSecureInputIsPassword() {
    #expect(classify("AXTextField", "AXSecureTextField") == .secure)
    #expect(classify(nil, secure: true) == .secure)
    #expect(classify("AXTextArea", secure: true) == .secure)
}

@Test func defaultsShowAutomaticallyButDoNotHide() {
    var policy = FocusPolicy()
    #expect(!policy.flickVisible)
    let shown = policy.observe(kind: .text, elementChanged: true)
    #expect(shown)
    #expect(policy.flickVisible)
    _ = policy.observe(kind: .none, elementChanged: true)
    _ = policy.observe(kind: .none, elementChanged: false)
    #expect(policy.kind == .none)
    #expect(policy.flickVisible)
}

@Test func autoShowCanBeTurnedOff() {
    var policy = FocusPolicy()
    policy.autoShow = false
    _ = policy.observe(kind: .text, elementChanged: true)
    #expect(!policy.flickVisible)
}

@Test func autoHideHidesOnlyAfterRepeatedObservation() {
    var policy = FocusPolicy()
    policy.autoHide = true
    _ = policy.observe(kind: .text, elementChanged: true)
    let first = policy.observe(kind: .none, elementChanged: true)
    #expect(!first)
    #expect(policy.flickVisible)
    // 戻ってくれば何も起きない
    let back = policy.observe(kind: .text, elementChanged: false)
    #expect(!back)
    #expect(policy.flickVisible)
    _ = policy.observe(kind: .none, elementChanged: true)
    let second = policy.observe(kind: .none, elementChanged: false)
    #expect(second)
    #expect(!policy.flickVisible)
}

@Test func manualToggleHoldsUntilFocusChanges() {
    var policy = FocusPolicy()
    _ = policy.observe(kind: .text, elementChanged: true)
    policy.userToggledFlick()
    #expect(!policy.flickVisible)
    let same = policy.observe(kind: .text, elementChanged: false)
    #expect(!same)
    #expect(!policy.flickVisible)
    let other = policy.observe(kind: .text, elementChanged: true)
    #expect(other)
    #expect(policy.flickVisible)
}

@Test func manualShowHoldsWhereFocusCannotBeDetected() {
    var policy = FocusPolicy()
    policy.autoHide = true
    policy.userToggledFlick()
    #expect(policy.flickVisible)
    _ = policy.observe(kind: .none, elementChanged: false)
    _ = policy.observe(kind: .none, elementChanged: false)
    #expect(policy.flickVisible)
}

@Test func passwordFieldHidesFlickButManualShowWorks() {
    var policy = FocusPolicy()
    _ = policy.observe(kind: .text, elementChanged: true)
    let secure = policy.observe(kind: .secure, elementChanged: true)
    #expect(secure)
    #expect(!policy.flickVisible)
    policy.userToggledFlick()
    #expect(policy.flickVisible)
    let same = policy.observe(kind: .secure, elementChanged: false)
    #expect(!same)
    #expect(policy.flickVisible)
}

@Test func transientFocusKeepsTextFocusAndManualState() {
    var policy = FocusPolicy()
    policy.autoHide = true
    _ = policy.observe(kind: .text, elementChanged: true)
    for _ in 0..<5 {
        let changed = policy.observe(kind: .transient, elementChanged: false)
        #expect(!changed)
    }
    #expect(policy.kind == .text)
    #expect(policy.flickVisible)

    // 手動で隠したあとに候補へ移って戻っても、再び出ない
    policy.userToggledFlick()
    _ = policy.observe(kind: .transient, elementChanged: false)
    let back = policy.observe(kind: .text, elementChanged: false)
    #expect(!back)
    #expect(!policy.flickVisible)
}

@Test func transientFocusAloneIsNotTextInput() {
    var policy = FocusPolicy()
    let changed = policy.observe(kind: .transient, elementChanged: false)
    #expect(!changed)
    #expect(policy.kind == .none)
    #expect(!policy.flickVisible)
}

@Test func leavingTransientForOtherElementCountsAsLeaving() {
    var policy = FocusPolicy()
    policy.autoHide = true
    _ = policy.observe(kind: .text, elementChanged: true)
    _ = policy.observe(kind: .transient, elementChanged: false)
    _ = policy.observe(kind: .none, elementChanged: true)
    _ = policy.observe(kind: .none, elementChanged: false)
    #expect(!policy.flickVisible)
}

/// 送信を記録する、パスワード欄の切り替えの確認用のパネル。
@MainActor
private final class FlickProbe {
    let panel = FlickPanel(origin: .zero, converter: nil, learningURL: URL(fileURLWithPath: "/dev/null"))
    var sentText: [String] = []
    var sentKeys: [TextSender.Key] = []

    init() {
        panel.sendText = { [unowned self] in self.sentText.append($0) }
        panel.sendKey = { [unowned self] in self.sentKeys.append($0) }
    }

    var keys: [KeyView] {
        panel.panel.contentView?.subviews.compactMap { $0 as? KeyView } ?? []
    }

    func key(_ label: String) -> KeyView? {
        keys.first { $0.label == label }
    }

    func key(symbol: String) -> KeyView? {
        keys.first { $0.symbolName == symbol }
    }

    func click(_ view: KeyView?) {
        view?.onEnd?(.zero, true)
    }
}

@MainActor @Test func normalFieldStillGoesThroughComposition() {
    let probe = FlickProbe()
    probe.click(probe.key("あ"))
    #expect(probe.panel.fieldText == "あ")
    probe.click(probe.key("ABC"))
    probe.click(probe.key("abc"))
    #expect(probe.panel.fieldText == "あa")
    #expect(probe.sentText.isEmpty)
    probe.click(probe.key(symbol: "paperplane"))
    #expect(probe.sentText == ["あa"])
    #expect(probe.panel.fieldText.isEmpty)
}

@MainActor @Test func passwordFieldSendsCharactersDirectly() {
    let probe = FlickProbe()
    probe.panel.setSecureFocused(true)
    probe.click(probe.key("abc"))
    probe.click(probe.key("123"))
    probe.click(probe.key("1"))
    #expect(probe.sentText == ["a", "1"])
    #expect(probe.panel.fieldText.isEmpty)
}

@MainActor @Test func passwordFieldSendsFunctionKeysDirectly() {
    let probe = FlickProbe()
    probe.click(probe.key("あ"))
    probe.panel.setSecureFocused(true)
    probe.click(probe.key(symbol: "delete.left"))
    probe.click(probe.key(symbol: "space"))
    probe.click(probe.key(symbol: "return"))
    #expect(probe.sentKeys == [.delete, .enter])
    #expect(probe.sentText == [" "])
    // 入力欄に残っていた文字には触らない
    #expect(probe.panel.fieldText == "あ")
}

@MainActor @Test func leftoverTextIsNeitherSentNorChanged() {
    let probe = FlickProbe()
    probe.click(probe.key("か"))
    probe.panel.setSecureFocused(true)
    #expect(probe.sentText.isEmpty)
    #expect(probe.panel.fieldText == "か")
    // 全削除のドラッグも働かない
    probe.key(symbol: "delete.left")?.onEnd?(CGVector(dx: -200, dy: 0), false)
    #expect(probe.panel.fieldText == "か")
    // 123 と ABC の切り替えで確定もしない。抜ければ、かなの未確定のまま続けられる
    probe.click(probe.key("123"))
    probe.panel.setSecureFocused(false)
    #expect(probe.panel.fieldText == "か")
    probe.click(probe.key("かな"))
    probe.click(probe.key("小゛゜"))
    #expect(probe.panel.fieldText == "が")
}

@MainActor @Test func kanaSwitchesToLatinAndKanaKeyIsDisabled() {
    let probe = FlickProbe()
    probe.panel.setSecureFocused(true)
    #expect(probe.key("abc") != nil)
    #expect(probe.key("あ") == nil)
    #expect(probe.key("かな")?.isEnabled == false)
    #expect(probe.key("かな")?.isDimmed == true)
    #expect(probe.key("ABC")?.isEnabled == true)
}

@MainActor @Test func leavingPasswordFieldRestoresNormalBehavior() {
    let probe = FlickProbe()
    probe.panel.setSecureFocused(true)
    probe.panel.setSecureFocused(false)
    #expect(probe.key("あ") != nil)
    #expect(probe.key("かな")?.isEnabled == true)
    #expect(probe.key("かな")?.isDimmed == false)
    probe.click(probe.key("あ"))
    #expect(probe.panel.fieldText == "あ")
    #expect(probe.sentText.isEmpty)
}

@MainActor @Test func manualModeIsKeptAfterLeavingPasswordField() {
    let probe = FlickProbe()
    probe.click(probe.key("123"))
    probe.panel.setSecureFocused(true)
    #expect(probe.key("1") != nil)
    probe.panel.setSecureFocused(false)
    #expect(probe.key("1") != nil)
}
