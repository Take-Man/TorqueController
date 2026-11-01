import CoreGraphics

enum TextSender {
    /// 文字列を Unicode 文字列のキーイベントとして送る。keyDown と keyUp を両方作れたときだけ送るので、押したままの状態は残らない。
    static func send(_ text: String) {
        let units = Array(text.utf16)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        for event in [down, up] {
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.post(tap: .cghidEventTap)
        }
    }
}
