import AppKit

/// QWERTY のキー。
enum QwertyKey: Equatable {
    case character(base: String, shifted: String)
    case delete, enter, space, tab, shift

    fileprivate static func letters(_ letters: String) -> [QwertyKey] {
        letters.map { .character(base: String($0), shifted: String($0).uppercased()) }
    }

    /// 行ごとのキーと、行の左端の字下げ(キーの幅に対する比)。各行の最後のキーは右端まで伸ばす。
    static let rows: [(indent: CGFloat, keys: [QwertyKey])] = [
        (0, [
            .character(base: "`", shifted: "~"), .character(base: "1", shifted: "!"), .character(base: "2", shifted: "@"),
            .character(base: "3", shifted: "#"), .character(base: "4", shifted: "$"), .character(base: "5", shifted: "%"),
            .character(base: "6", shifted: "^"), .character(base: "7", shifted: "&"), .character(base: "8", shifted: "*"),
            .character(base: "9", shifted: "("), .character(base: "0", shifted: ")"), .character(base: "-", shifted: "_"),
            .character(base: "=", shifted: "+"), .delete,
        ]),
        (0.5, letters("qwertyuiop") + [
            .character(base: "[", shifted: "{"), .character(base: "]", shifted: "}"), .character(base: "\\", shifted: "|"),
        ]),
        (0, [.tab] + letters("asdfghjkl") + [
            .character(base: ";", shifted: ":"), .character(base: "'", shifted: "\""), .enter,
        ]),
        (0, [.shift] + letters("zxcvbnm") + [
            .character(base: ",", shifted: "<"), .character(base: ".", shifted: ">"), .character(base: "/", shifted: "?"), .space,
        ]),
    ]

    /// キーの幅(1 が通常のキー)。
    var widthUnits: CGFloat {
        switch self {
        case .character, .tab, .enter, .space: 1
        case .delete, .shift: 1.5
        }
    }
}

/// QWERTY の英字キーボード。押されたキーを伝えるだけで、送信はコンパクトなキーボードが受け持つ。
@MainActor
final class QwertyKeyboard {
    private enum Metrics {
        static let keySide: CGFloat = 44
        static let gap: CGFloat = 4
        static let padding: CGFloat = 8
    }

    /// 押されたキー。シフトキーはここで処理して伝えない。
    var onKey: ((QwertyKey) -> Void)?

    private let panel: KeyPanel
    private var keyViews: [(key: QwertyKey, view: KeyView)] = []
    /// スマートフォンと同じく、1回で次の1文字だけ、連続2回で固定(CapsLock)。
    private var shift = LatchState.off
    private var modifiers: Set<Modifier> = []
    private var highlighted: Set<String> = []

    var isVisible: Bool { panel.isVisible }
    /// origin はパネルの左下。
    init(origin: NSPoint) {
        var maxWidth: CGFloat = 0
        let step = Metrics.keySide + Metrics.gap
        let rowCount = QwertyKey.rows.count
        var rows: [[(key: QwertyKey, frame: NSRect)]] = []
        for (rowIndex, row) in QwertyKey.rows.enumerated() {
            var x = Metrics.padding + row.indent * step
            let y = Metrics.padding + CGFloat(rowCount - 1 - rowIndex) * step
            var keys: [(key: QwertyKey, frame: NSRect)] = []
            for key in row.keys {
                let width = key.widthUnits * Metrics.keySide + (key.widthUnits - 1) * Metrics.gap
                keys.append((key, NSRect(x: x, y: y, width: width, height: Metrics.keySide)))
                x += width + Metrics.gap
            }
            maxWidth = max(maxWidth, x - Metrics.gap + Metrics.padding)
            rows.append(keys)
        }
        for index in rows.indices {
            guard let last = rows[index].last else { continue }
            rows[index][rows[index].count - 1].frame.size.width = maxWidth - Metrics.padding - last.frame.minX
        }
        let layout = rows.joined()
        let size = NSSize(width: maxWidth, height: CGFloat(rowCount) * step - Metrics.gap + Metrics.padding * 2)
        panel = KeyPanel(contentRect: NSRect(origin: origin, size: size))
        let background = PanelBackgroundView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = background

        // q の左の余白に持ち手を置く
        if let q = rows[1].first?.frame {
            let grip = GripView(frame: NSRect(x: Metrics.padding, y: q.minY, width: q.minX - Metrics.gap - Metrics.padding, height: q.height))
            background.addSubview(grip)
        }

        for (key, frame) in layout {
            let view = KeyView()
            view.frame = frame
            view.onEnd = { [weak self] _, isInside in
                if isInside {
                    self?.pressed(key, clickCount: view.clickCount)
                }
            }
            background.addSubview(view)
            keyViews.append((key, view))
        }
        refresh()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setEnabled(_ isEnabled: Bool) {
        for (_, view) in keyViews {
            view.isEnabled = isEnabled
        }
    }

    /// 選択中の修飾キーと、ハイライトするキーを設定する。
    func update(modifiers: Set<Modifier>, highlighted: Set<String>) {
        self.modifiers = modifiers
        self.highlighted = highlighted
        refresh()
    }

    /// 今の表示で、そのキーが入力する文字。
    func displayed(base: String, shifted: String) -> String {
        // 修飾キーと組み合わせるときは、設定と同じ元の文字を見せる
        if !modifiers.isEmpty, modifiers != [.shift] {
            return base
        }
        if modifiers == [.shift] || shift == .once {
            return shifted
        }
        // 固定は CapsLock と同じく英字だけに効く
        return shift == .locked && base.first?.isLetter == true ? shifted : base
    }

    /// 文字を1つ入力した後に呼ぶ。1回だけのシフトを解除する。
    func characterEntered() {
        shift = shift.afterInput
        refresh()
    }

    private func pressed(_ key: QwertyKey, clickCount: Int) {
        if key == .shift {
            shift = shift.pressed(isDoubleClick: clickCount == 2)
            refresh()
        } else {
            onKey?(key)
        }
    }

    private func refresh() {
        for (key, view) in keyViews {
            switch key {
            case .character(let base, let shifted):
                view.label = displayed(base: base, shifted: shifted)
                view.isMarked = highlighted.contains(base)
            case .delete:
                view.symbolName = "delete.left"
            case .enter:
                view.symbolName = "return"
            case .space:
                view.symbolName = "space"
            case .tab:
                view.symbolName = "arrow.right.to.line"
            case .shift:
                view.symbolName = shift.shiftSymbol
            }
        }
    }
}
