import CoreGraphics

enum FlickDirection: CaseIterable {
    case left, up, right, down

    /// 押した位置からの移動量で方向を決める。y は上が正。中心の領域の中なら nil。
    static func from(offset: CGVector, deadZone: CGFloat) -> FlickDirection? {
        guard hypot(offset.dx, offset.dy) >= deadZone else { return nil }
        if abs(offset.dx) > abs(offset.dy) {
            return offset.dx < 0 ? .left : .right
        }
        return offset.dy > 0 ? .up : .down
    }
}

struct FlickCharacters: Equatable {
    let label: String
    let center: String
    let outer: [FlickDirection: String]

    /// 中央、左、上、右、下の順に並べた文字から作る。空文字列はその方向に文字がないことを表す。
    init(_ characters: String..., label: String? = nil) {
        center = characters[0]
        self.label = label ?? characters[0]
        var outer: [FlickDirection: String] = [:]
        for (direction, character) in zip(FlickDirection.allCases, characters.dropFirst()) where !character.isEmpty {
            outer[direction] = character
        }
        self.outer = outer
    }

    private init(label: String, center: String, outer: [FlickDirection: String]) {
        self.label = label
        self.center = center
        self.outer = outer
    }

    func character(in direction: FlickDirection?) -> String? {
        direction.map { outer[$0] } ?? center
    }

    var uppercased: FlickCharacters {
        FlickCharacters(label: label.uppercased(), center: center.uppercased(), outer: outer.mapValues { $0.uppercased() })
    }
}

enum GridKey: Equatable {
    case flick(FlickCharacters)
    case cycle(label: String)
    case shift

    var label: String {
        switch self {
        case .flick(let characters): characters.label
        case .cycle(let label): label
        case .shift: ""
        }
    }

    var uppercased: GridKey {
        if case .flick(let characters) = self {
            return .flick(characters.uppercased)
        }
        return self
    }
}

/// 英字の大文字入力の状態。スマートフォンのシフトキーと同じく、1回で次の1文字だけ大文字、連続2回で固定。
enum ShiftState {
    case off, once, locked

    func pressed(isDoubleClick: Bool) -> ShiftState {
        switch self {
        case .off: .once
        case .once: isDoubleClick ? .locked : .off
        case .locked: .off
        }
    }

    var afterInput: ShiftState {
        self == .once ? .off : self
    }

    var symbolName: String {
        switch self {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }
}

enum InputMode: CaseIterable {
    case kana, symbol, latin

    var label: String {
        switch self {
        case .kana: "かな"
        case .symbol: "123"
        case .latin: "ABC"
        }
    }

    /// 3列×4行のキー。あ段は中央、い段は左、う段は上、え段は右、お段は下。
    var grid: [GridKey] {
        switch self {
        case .kana: Self.kanaGrid
        case .symbol: Self.symbolGrid
        case .latin: Self.latinGrid
        }
    }

    private static let kanaGrid: [GridKey] = [
        .flick(.init("あ", "い", "う", "え", "お")),
        .flick(.init("か", "き", "く", "け", "こ")),
        .flick(.init("さ", "し", "す", "せ", "そ")),
        .flick(.init("た", "ち", "つ", "て", "と")),
        .flick(.init("な", "に", "ぬ", "ね", "の")),
        .flick(.init("は", "ひ", "ふ", "へ", "ほ")),
        .flick(.init("ま", "み", "む", "め", "も")),
        .flick(.init("や", "（", "ゆ", "）", "よ")),
        .flick(.init("ら", "り", "る", "れ", "ろ")),
        .cycle(label: "小゛゜"),
        .flick(.init("わ", "を", "ん", "ー")),
        .flick(.init("、", "。", "？", "！", "…", label: "、。?!")),
    ]

    private static let symbolGrid: [GridKey] = [
        .flick(.init("1", "☆", "♪", "→")),
        .flick(.init("2", "¥", "$", "€")),
        .flick(.init("3", "%", "°", "#")),
        .flick(.init("4", "○", "*", "・")),
        .flick(.init("5", "+", "×", "÷")),
        .flick(.init("6", "<", "=", ">")),
        .flick(.init("7", "「", "」", ":")),
        .flick(.init("8", "〒", "々", "〆")),
        .flick(.init("9", "^", "|", "\\")),
        .flick(.init("(", ")", "[", "]")),
        .flick(.init("0", "〜", "…")),
        .flick(.init(".", ",", "-", "/")),
    ]

    private static let latinGrid: [GridKey] = [
        .flick(.init("@", "#", "/", "&", "_", label: "@#/&_")),
        .flick(.init("a", "b", "c", label: "abc")),
        .flick(.init("d", "e", "f", label: "def")),
        .flick(.init("g", "h", "i", label: "ghi")),
        .flick(.init("j", "k", "l", label: "jkl")),
        .flick(.init("m", "n", "o", label: "mno")),
        .flick(.init("p", "q", "r", "s", label: "pqrs")),
        .flick(.init("t", "u", "v", label: "tuv")),
        .flick(.init("w", "x", "y", "z", label: "wxyz")),
        .shift,
        .flick(.init("'", "\"", "(", ")", label: "'\"()")),
        .flick(.init(".", ",", "?", "!", label: ".,?!")),
    ]
}
