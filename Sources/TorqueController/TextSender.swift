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

    struct Stroke: Equatable {
        let keyCode: CGKeyCode
        let isDown: Bool
        let flags: CGEventFlags
        let isModifier: Bool
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
        post(virtualKey: key.rawValue, unicode: nil, modifiers: modifiers)
    }

    /// ショートカットを、修飾キーを押す、キーを押して離す、修飾キーを離す、の一続きで送る。
    static func send(character: String, modifiers: Set<Modifier>) {
        guard let code = KeyboardLayout.keyCode(for: character) else {
            NSLog("キーコードが見つかりません: %@", character)
            return
        }
        post(virtualKey: code, unicode: nil, modifiers: modifiers)
    }

    /// 修飾キー単体を送る。常に左側のキーコードで、押して離すまでを1組で送る。
    static func send(modifier: Modifier) {
        post(virtualKey: nil, unicode: nil, modifiers: [modifier])
    }

    /// 送るイベントの順序とフラグ。最後のイベントは必ずフラグなしになる。
    /// AirController はキーイベントのフラグを実際に押している修飾キーとして覚えてクリックに付けるので、
    /// フラグを残して終わると、以後のクリックがずっと修飾キー付きになる。
    static func strokes(virtualKey: CGKeyCode?, modifiers: Set<Modifier>) -> [Stroke] {
        let ordered = Modifier.allCases.filter(modifiers.contains)
        var result: [Stroke] = []
        var held: CGEventFlags = []
        for modifier in ordered {
            held.insert(modifier.flag)
            result.append(Stroke(keyCode: modifier.leftKeyCode, isDown: true, flags: held, isModifier: true))
        }
        if let virtualKey {
            result.append(Stroke(keyCode: virtualKey, isDown: true, flags: modifiers.flags, isModifier: false))
            result.append(Stroke(keyCode: virtualKey, isDown: false, flags: modifiers.flags, isModifier: false))
        }
        for modifier in ordered.reversed() {
            held.remove(modifier.flag)
            result.append(Stroke(keyCode: modifier.leftKeyCode, isDown: false, flags: held, isModifier: true))
        }
        return result
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

    /// 全てのイベントを作れたときだけ送るので、押したままの状態は残らない。
    private static func post(virtualKey: CGKeyCode?, unicode: [UniChar]?, modifiers: Set<Modifier> = []) {
        guard let source = CGEventSource(stateID: .privateState) else { return }

        var events: [CGEvent] = []
        for stroke in strokes(virtualKey: virtualKey, modifiers: modifiers) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: stroke.isDown)
            else { return }
            if stroke.isModifier {
                event.type = .flagsChanged
            } else if let unicode {
                event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            event.flags = stroke.flags
            events.append(event)
        }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
    }
}
