import CoreGraphics
import Foundation

enum TextSender {
    enum Key: CGKeyCode {
        case delete = 51
        case enter = 36
        case space = 49
        case tab = 48
        case escape = 53
        case leftArrow = 123
        case rightArrow = 124
        case downArrow = 125
        case upArrow = 126
    }

    /// 1つのイベントに載せる UTF-16 の上限。これより長い文字列は実機で切れるという情報があるので分けて送る。
    private static let maxUnitsPerEvent = 20

    /// 文字列を Unicode 文字列のキーイベントとして送る。
    static func send(_ text: String) {
        for chunk in chunks(of: text, maxUnits: maxUnitsPerEvent) {
            post(virtualKey: 0, unicode: Array(chunk.utf16))
        }
    }

    static func send(_ key: Key, modifiers: Set<Modifier> = []) {
        post(virtualKey: key.rawValue, unicode: nil, flags: modifiers.flags)
    }

    /// ショートカットを、修飾フラグ付きの1つのキーイベントとして送る。修飾キーを押したままにはしない。
    static func send(character: String, modifiers: Set<Modifier>) {
        guard let code = KeyboardLayout.keyCode(for: character) else {
            NSLog("キーコードが見つかりません: %@", character)
            return
        }
        post(virtualKey: code, unicode: nil, flags: modifiers.flags)
    }

    /// 修飾キー単体を送る。常に左側のキーコードで、押して離すまでを1組で送る。
    static func send(modifier: Modifier) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: modifier.leftKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: modifier.leftKeyCode, keyDown: false)
        else { return }
        down.flags = modifier.flag
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
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
    private static func post(virtualKey: CGKeyCode, unicode: [UniChar]?, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return }

        for event in [down, up] {
            event.flags = flags
            if let unicode {
                event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            event.post(tap: .cghidEventTap)
        }
    }
}
