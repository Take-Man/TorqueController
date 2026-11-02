/// 入力欄の文字列。確定済みの部分と、その後ろの未確定のかなからなる。
struct Composition {
    private(set) var confirmed = ""
    private(set) var pending = ""

    var isEmpty: Bool { confirmed.isEmpty && pending.isEmpty }
    var text: String { confirmed + pending }

    mutating func appendPending(_ string: String) {
        pending += string
    }

    mutating func appendConfirmed(_ string: String) {
        confirmPending()
        confirmed += string
    }

    /// 未確定のかなを、かなのまま確定にする。
    mutating func confirmPending() {
        confirmed += pending
        pending = ""
    }

    /// 変換で選んだ文字列を確定に加え、未確定を残りの読みに置き換える。
    mutating func applyConversion(converted: String, remaining: String) {
        confirmed += converted
        pending = remaining
    }

    /// 未確定の末尾を消す。未確定がなければ確定済みの末尾を消す。
    mutating func deleteLast() {
        if !pending.isEmpty {
            pending.removeLast()
        } else if !confirmed.isEmpty {
            confirmed.removeLast()
        }
    }

    mutating func clear() {
        confirmed = ""
        pending = ""
    }

    /// 未確定の直前の1文字を巡回させる(は→ば→ぱ→は)。
    mutating func cycleLast() {
        guard let last = pending.last, let next = Self.nextInCycle(of: last) else { return }
        pending.removeLast()
        pending.append(next)
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
