import AppKit

/// QWERTY パネルの表示状態。修飾キーの選択で自動で出したものは、選択が空になると隠す。切替キーの操作は常に優先する。
struct QwertyVisibility: Equatable {
    private(set) var isVisible = false
    private var wasAutoShown = false

    mutating func modifierSelected() {
        if !isVisible {
            isVisible = true
            wasAutoShown = true
        }
    }

    mutating func selectionEmptied() {
        if wasAutoShown {
            isVisible = false
            wasAutoShown = false
        }
    }

    mutating func toggled() {
        isVisible.toggle()
        wasAutoShown = false
    }
}

/// 常に表示するコンパクトパネル。3列×4行の格子で、1行目に Esc と円形の QWERTY、フリックの切替キー、
/// 左の列に ⌃ と ⇧、下の行に ⌥ と ⌘、中央から右に十字キーを置く。左下の余白は持ち手。
/// 修飾キーのクリックがショートカット入力A、修飾キーからのドラッグがショートカット入力B。
@MainActor
final class CompactKeyboard {
    private enum Metrics {
        static let keySide: CGFloat = 44
        static let gap: CGFloat = 6
        static let padding: CGFloat = 8
        static let columns = 3
        static let rows = 4
        /// これより動かすと、クリックではなくドラッグとして扱う。
        static let dragThreshold: CGFloat = 8
    }

    static let width = CGFloat(Metrics.columns) * Metrics.keySide + CGFloat(Metrics.columns - 1) * Metrics.gap + Metrics.padding * 2
    private static let height = CGFloat(Metrics.rows) * Metrics.keySide + CGFloat(Metrics.rows - 1) * Metrics.gap + Metrics.padding * 2

    /// フリックの表示切替。今の表示状態を返す。
    var onToggleFlick: (() -> Bool)?

    private let panel: KeyPanel
    private let radialPanel: KeyPanel
    private let radialView = ShortcutRadialView()
    private let qwerty: QwertyKeyboard
    private var modifierViews: [Modifier: KeyView] = [:]
    private let escapeView = KeyView(label: "esc")
    private let dPadView = DPadView()
    private let qwertyToggleView = KeyView(symbolName: "keyboard")
    private let flickToggleView = KeyView(symbolName: "square.grid.3x3")

    private var shortcuts: [Shortcut]
    private var states: [Modifier: LatchState] = [:]
    private var qwertyVisibility = QwertyVisibility()
    private var isDragging = false
    private var radial: ShortcutRadial?

    private var activeModifiers: Set<Modifier> {
        Set(states.filter { $0.value != .off }.keys)
    }

    /// origin はパネルの左下。qwertyOrigin は QWERTY の左下。
    init(origin: NSPoint, qwertyOrigin: NSPoint, shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
        let size = NSSize(width: Self.width, height: Self.height)
        panel = KeyPanel(contentRect: NSRect(origin: origin, size: size))
        let background = PanelBackgroundView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = background

        radialPanel = KeyPanel(contentRect: .zero)
        radialPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        radialPanel.ignoresMouseEvents = true
        radialPanel.hasShadow = false
        radialPanel.contentView = radialView

        qwerty = QwertyKeyboard(origin: qwertyOrigin)
        qwerty.onKey = { [weak self] key in self?.qwertyPressed(key) }

        func frame(column: Int, row: Int) -> NSRect {
            NSRect(
                x: Metrics.padding + CGFloat(column) * (Metrics.keySide + Metrics.gap),
                y: Metrics.padding + CGFloat(Metrics.rows - 1 - row) * (Metrics.keySide + Metrics.gap),
                width: Metrics.keySide,
                height: Metrics.keySide
            )
        }

        escapeView.frame = frame(column: 0, row: 0)
        escapeView.onEnd = { [weak self] _, isInside in
            if isInside {
                self?.escapePressed()
            }
        }
        background.addSubview(escapeView)

        let placement: [(Modifier, Int, Int)] = [(.control, 0, 1), (.shift, 0, 2), (.option, 1, 3), (.command, 2, 3)]
        for (modifier, column, row) in placement {
            let view = KeyView(label: modifier.symbol)
            view.frame = frame(column: column, row: row)
            view.keepsPressedOutside = true
            view.onBegin = { [weak self] _ in self?.isDragging = false }
            view.onDrag = { [weak self] offset in self?.modifierDragged(modifier, view: view, offset: offset) }
            view.onEnd = { [weak self] offset, isInside in
                self?.modifierEnded(modifier, offset: offset, isInside: isInside, clickCount: view.clickCount)
            }
            background.addSubview(view)
            modifierViews[modifier] = view
        }

        // 左下の余白は持ち手
        background.addSubview(GripView(frame: frame(column: 0, row: 3)))

        // 2キー分の正方形に十字キーの円を置く
        dPadView.frame = frame(column: 1, row: 2).union(frame(column: 2, row: 1))
        dPadView.onArrow = { [weak self] direction in
            guard let self else { return }
            TextSender.send(direction.key, modifiers: self.activeModifiers)
        }
        dPadView.onRelease = { [weak self] in self?.releaseSelection() }
        background.addSubview(dPadView)

        qwertyToggleView.frame = frame(column: 1, row: 0)
        qwertyToggleView.cornerRadius = Metrics.keySide / 2
        qwertyToggleView.onEnd = { [weak self] _, isInside in
            if isInside {
                self?.toggleQwerty()
            }
        }
        background.addSubview(qwertyToggleView)

        flickToggleView.frame = frame(column: 2, row: 0)
        flickToggleView.cornerRadius = Metrics.keySide / 2
        flickToggleView.isSelected = true
        flickToggleView.onEnd = { [weak self] _, isInside in
            guard isInside, let self else { return }
            self.flickToggleView.isSelected = self.onToggleFlick?() ?? false
        }
        background.addSubview(flickToggleView)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func setEnabled(_ isEnabled: Bool) {
        for view in Array(modifierViews.values) + [escapeView, qwertyToggleView, flickToggleView] {
            view.isEnabled = isEnabled
        }
        dPadView.isEnabled = isEnabled
        qwerty.setEnabled(isEnabled)
    }

    func setShortcuts(_ shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
        applySelection()
    }

    // MARK: - ショートカット入力A

    /// クリックで選択し、ダブルクリックで固定する。固定中のクリックで解除する。
    private func clicked(_ modifier: Modifier, clickCount: Int) {
        let state = (states[modifier] ?? .off).pressed(isDoubleClick: clickCount == 2)
        states[modifier] = state
        if state != .off {
            qwertyVisibility.modifierSelected()
        }
        applySelection()
    }

    /// 選択に合わせて、修飾キーの表示、QWERTY の表示、ハイライトを更新する。
    private func applySelection() {
        for (modifier, view) in modifierViews {
            let state = states[modifier] ?? .off
            view.isSelected = state != .off
            view.hints = state == .locked ? [.down: "●"] : [:]
        }
        let active = activeModifiers
        let highlighted = active.isEmpty ? [] : Set(shortcuts.filter { $0.modifiers == active }.map(\.key))
        qwerty.update(modifiers: active, highlighted: highlighted)

        if active.isEmpty {
            qwertyVisibility.selectionEmptied()
        }
        if qwertyVisibility.isVisible {
            qwerty.show()
        } else {
            qwerty.hide()
        }
        qwertyToggleView.isSelected = qwertyVisibility.isVisible
    }

    private func toggleQwerty() {
        qwertyVisibility.toggled()
        applySelection()
    }

    private func qwertyPressed(_ key: QwertyKey) {
        let active = activeModifiers
        let typesText = active.isEmpty || active == [.shift]
        switch key {
        case .character(let base, let shifted):
            if typesText {
                TextSender.send(qwerty.displayed(base: base, shifted: shifted))
                qwerty.characterEntered()
            } else {
                TextSender.send(character: base, modifiers: active)
            }
        case .space:
            if typesText {
                TextSender.send(" ")
            } else {
                TextSender.send(.space, modifiers: active)
            }
        case .delete:
            TextSender.send(.delete, modifiers: active)
        case .enter:
            TextSender.send(.enter, modifiers: active)
        case .tab:
            TextSender.send(.tab, modifiers: active)
        case .shift:
            return
        }
        releaseSelection()
    }

    private func escapePressed() {
        TextSender.send(.escape, modifiers: activeModifiers)
        releaseSelection()
    }

    /// 1回送ると選択は解除する。固定したものは残る。
    private func releaseSelection() {
        for (modifier, state) in states {
            states[modifier] = state.afterInput
        }
        applySelection()
    }

    // MARK: - ショートカット入力B

    private func modifierDragged(_ modifier: Modifier, view: KeyView, offset: CGVector) {
        if !isDragging {
            guard hypot(offset.dx, offset.dy) >= Metrics.dragThreshold else { return }
            isDragging = true
            showRadial(modifier, view: view, offset: offset)
        }
        if let radial {
            radialView.selection = radial.selection(offset: offset)
        }
    }

    private func modifierEnded(_ modifier: Modifier, offset: CGVector, isInside: Bool, clickCount: Int) {
        guard isDragging else {
            if isInside {
                clicked(modifier, clickCount: clickCount)
            }
            return
        }
        isDragging = false
        radialPanel.orderOut(nil)
        guard let radial else { return }
        switch radial.selection(offset: offset) {
        case .center:
            TextSender.send(modifier: modifier)
        case .cancel:
            break
        case .path(let path):
            if case .key(let shortcut)? = path.last?.kind {
                TextSender.send(character: shortcut.key, modifiers: shortcut.modifiers)
            }
        }
        self.radial = nil
    }

    private func showRadial(_ modifier: Modifier, view: KeyView, offset: CGVector) {
        let radial = ShortcutRadial(origin: modifier, shortcuts: shortcuts)
        self.radial = radial
        radialView.radial = radial

        // 中心は押した位置。今のカーソルの位置から移動量を引いて求める
        let location = NSEvent.mouseLocation
        let center = NSPoint(x: location.x - offset.dx, y: location.y - offset.dy)
        let radius = ShortcutRadial.maxRadius(depth: radial.depth) + 2
        radialPanel.setFrame(NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), display: true)
        radialPanel.orderFrontRegardless()
    }
}
