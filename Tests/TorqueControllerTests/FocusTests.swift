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
    #expect(classify("AXStaticText") == .none)
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
