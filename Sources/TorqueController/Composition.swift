/// キーボード側で持つ未確定文字列。
struct Composition {
    private(set) var text = ""

    var isEmpty: Bool { text.isEmpty }

    mutating func append(_ string: String) {
        text += string
    }

    mutating func deleteLast() {
        if !text.isEmpty {
            text.removeLast()
        }
    }

    mutating func clear() {
        text = ""
    }

    /// 直前の1文字を巡回させる(は→ば→ぱ→は)。
    mutating func cycleLast() {
        guard let last = text.last, let next = Self.nextInCycle(of: last) else { return }
        text.removeLast()
        text.append(next)
    }

    private static func nextInCycle(of character: Character) -> Character? {
        for group in cycleGroups {
            if let index = group.firstIndex(of: character) {
                return group[(index + 1) % group.count]
            }
        }
        return nil
    }

    private static let cycleGroups: [[Character]] = [
        ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ", "ゔ"], ["え", "ぇ"], ["お", "ぉ"],
        ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
        ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
        ["た", "だ"], ["ち", "ぢ"], ["つ", "っ", "づ"], ["て", "で"], ["と", "ど"],
        ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
        ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["わ", "ゎ"],
    ]
}
