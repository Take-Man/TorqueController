import CoreGraphics

enum TextSender {
    enum Key: CGKeyCode {
        case delete = 51
        case enter = 36
    }

    /// 1つのイベントに載せる UTF-16 の上限。これより長い文字列は実機で切れるという情報があるので分けて送る。
    private static let maxUnitsPerEvent = 20

    /// 文字列を Unicode 文字列のキーイベントとして送る。
    static func send(_ text: String) {
        for chunk in chunks(of: text, maxUnits: maxUnitsPerEvent) {
            post(virtualKey: 0, unicode: Array(chunk.utf16))
        }
    }

    static func send(_ key: Key) {
        post(virtualKey: key.rawValue, unicode: nil)
    }

    /// 文字の途中で切らずに、上限以下の長さに分ける。
    static func chunks(of text: String, maxUnits: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if current.utf16.count + character.utf16.count > maxUnits {
                result.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// keyDown と keyUp を両方作れたときだけ送るので、押したままの状態は残らない。
    private static func post(virtualKey: CGKeyCode, unicode: [UniChar]?) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return }

        for event in [down, up] {
            event.flags = []
            if let unicode {
                event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            event.post(tap: .cghidEventTap)
        }
    }
}
