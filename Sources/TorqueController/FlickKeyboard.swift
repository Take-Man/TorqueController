import AppKit

/// フリックのキーボード。パネル、ガイド、未確定文字列を持ち、キーの操作を入力に変える。
@MainActor
final class FlickKeyboard {
    private enum Metrics {
        static let keySide: CGFloat = 56
        static let sideKeyWidth: CGFloat = 44
        static let gap: CGFloat = 6
        static let padding: CGFloat = 8
        static let compositionHeight: CGFloat = 40
        static let rows = 4
        static let gridColumns = 3
        /// ガイドの下の区画の文字が画面の下端で切れないよう、パネルを画面下端から離す距離。
        static let minScreenBottomMargin: CGFloat = 60
        static let screenMargin: CGFloat = 16
    }

    private let panel: KeyPanel
    private let guidePanel: KeyPanel
    private let guideView = FlickGuideView()
    private let compositionView = CompositionView()
    private var gridViews: [KeyView] = []
    private var modeViews: [InputMode: KeyView] = [:]
    private let deleteView = KeyView(symbolName: "delete.left")
    private let spaceView = KeyView(symbolName: "space")
    private let enterView = KeyView(symbolName: FlickKeyboard.enterSymbol)

    private static let enterSymbol = "return"

    private var composition = Composition()
    private var mode = InputMode.kana
    private var shift = ShiftState.off

    /// 今の入力モードとシフトの状態で表示するキー。
    private var grid: [GridKey] {
        shift == .off ? mode.grid : mode.grid.map(\.uppercased)
    }

    init() {
        let gridHeight = CGFloat(Metrics.rows) * Metrics.keySide + CGFloat(Metrics.rows - 1) * Metrics.gap
        let contentWidth = Metrics.sideKeyWidth * 2 + CGFloat(Metrics.gridColumns) * Metrics.keySide + CGFloat(Metrics.gridColumns + 1) * Metrics.gap
        let size = NSSize(
            width: contentWidth + Metrics.padding * 2,
            height: gridHeight + Metrics.compositionHeight + Metrics.gap + Metrics.padding * 2
        )
        panel = KeyPanel(contentRect: NSRect(origin: Self.initialOrigin(), size: size))

        let guideSide = (FlickGuideView.outerRadius + 2) * 2
        guidePanel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: guideSide, height: guideSide))
        guidePanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        guidePanel.ignoresMouseEvents = true
        guidePanel.contentView = guideView

        let background = PanelBackgroundView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = background

        compositionView.frame = NSRect(
            x: Metrics.padding,
            y: Metrics.padding + gridHeight + Metrics.gap,
            width: contentWidth,
            height: Metrics.compositionHeight
        )
        background.addSubview(compositionView)

        layoutGrid(in: background, gridHeight: gridHeight)
        layoutSideColumns(in: background, gridHeight: gridHeight)
        applyMode()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func setEnabled(_ isEnabled: Bool) {
        for view in gridViews + Array(modeViews.values) + [deleteView, spaceView, enterView] {
            view.isEnabled = isEnabled
        }
    }

    private static func initialOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.minX + Metrics.screenMargin,
            y: max(screen.visibleFrame.minY + Metrics.screenMargin, screen.frame.minY + Metrics.minScreenBottomMargin)
        )
    }

    // MARK: - 配置

    private func layoutGrid(in background: NSView, gridHeight: CGFloat) {
        let step = Metrics.keySide + Metrics.gap
        for index in 0..<(Metrics.rows * Metrics.gridColumns) {
            let column = index % Metrics.gridColumns
            let row = index / Metrics.gridColumns
            let view = KeyView()
            view.frame = NSRect(
                x: Metrics.padding + Metrics.sideKeyWidth + Metrics.gap + step * CGFloat(column),
                y: Metrics.padding + gridHeight - Metrics.keySide - step * CGFloat(row),
                width: Metrics.keySide,
                height: Metrics.keySide
            )
            view.onBegin = { [weak self] location in self?.gridKeyBegan(index, at: location) }
            view.onDrag = { [weak self] offset in self?.gridKeyDragged(index, offset: offset) }
            view.onEnd = { [weak self] offset, isInside in self?.gridKeyEnded(index, offset: offset, isInside: isInside) }
            background.addSubview(view)
            gridViews.append(view)
        }
    }

    /// 左列(入力の切替)と右列(削除、空白、改行・確定)は、それぞれ3つのキーで高さを等分する。
    private func layoutSideColumns(in background: NSView, gridHeight: CGFloat) {
        let height = (gridHeight - Metrics.gap * 2) / 3
        let leftX = Metrics.padding
        let rightX = Metrics.padding + Metrics.sideKeyWidth + Metrics.gap + (Metrics.keySide + Metrics.gap) * CGFloat(Metrics.gridColumns)
        func frame(x: CGFloat, position: Int) -> NSRect {
            NSRect(
                x: x,
                y: Metrics.padding + gridHeight - height - (height + Metrics.gap) * CGFloat(position),
                width: Metrics.sideKeyWidth,
                height: height
            )
        }

        for (position, mode) in InputMode.allCases.enumerated() {
            let view = KeyView(label: mode.label)
            view.frame = frame(x: leftX, position: position)
            view.onEnd = { [weak self] _, isInside in
                if isInside {
                    self?.mode = mode
                    self?.shift = .off
                    self?.applyMode()
                }
            }
            background.addSubview(view)
            modeViews[mode] = view
        }

        let actions: [(KeyView, @MainActor () -> Void)] = [
            (deleteView, { [weak self] in self?.deletePressed() }),
            (spaceView, { [weak self] in self?.spacePressed() }),
            (enterView, { [weak self] in self?.enterPressed() }),
        ]
        for (position, (view, action)) in actions.enumerated() {
            view.frame = frame(x: rightX, position: position)
            view.onEnd = { _, isInside in
                if isInside {
                    action()
                }
            }
            background.addSubview(view)
        }
    }

    private func applyMode() {
        for (view, key) in zip(gridViews, grid) {
            view.label = key.label
            view.symbolName = nil
            view.isSelected = false
            view.keepsPressedOutside = false
            view.hints = [:]
            switch key {
            case .flick(let characters):
                view.keepsPressedOutside = true
                if mode == .symbol {
                    view.hints = characters.outer
                }
            case .shift:
                view.symbolName = shift.symbolName
                view.isSelected = shift != .off
            case .cycle:
                break
            }
        }
        for (mode, view) in modeViews {
            view.isSelected = mode == self.mode
        }
    }

    // MARK: - フリック

    private func gridKeyBegan(_ index: Int, at location: NSPoint) {
        guard case .flick(let characters) = grid[index] else { return }
        guideView.characters = characters
        guideView.direction = nil
        let side = guidePanel.frame.width
        guidePanel.setFrameOrigin(NSPoint(x: location.x - side / 2, y: location.y - side / 2))
        guidePanel.orderFrontRegardless()
    }

    private func gridKeyDragged(_ index: Int, offset: CGVector) {
        guard case .flick = grid[index] else { return }
        guideView.direction = FlickDirection.from(offset: offset, deadZone: FlickGuideView.innerRadius)
    }

    private func gridKeyEnded(_ index: Int, offset: CGVector, isInside: Bool) {
        switch grid[index] {
        case .flick(let characters):
            guidePanel.orderOut(nil)
            let direction = FlickDirection.from(offset: offset, deadZone: FlickGuideView.innerRadius)
            if let character = characters.character(in: direction) {
                composition.append(character)
                compositionChanged()
                shift = shift.afterInput
                applyMode()
            }
        case .cycle:
            if isInside {
                composition.cycleLast()
                compositionChanged()
            }
        case .shift:
            if isInside {
                shift = shift.pressed(isDoubleClick: gridViews[index].clickCount == 2)
                applyMode()
            }
        }
    }

    // MARK: - 機能キー

    private func deletePressed() {
        if composition.isEmpty {
            TextSender.send(.delete)
        } else {
            composition.deleteLast()
            compositionChanged()
        }
    }

    /// 未確定文字列があるときの空白キーは変換の開始に使うので、ここでは空白を入れない。
    private func spacePressed() {
        if composition.isEmpty {
            TextSender.send(" ")
        }
    }

    private func enterPressed() {
        if composition.isEmpty {
            TextSender.send(.enter)
        } else {
            TextSender.send(composition.text)
            composition.clear()
            compositionChanged()
        }
    }

    private func compositionChanged() {
        compositionView.text = composition.text
        enterView.symbolName = composition.isEmpty ? Self.enterSymbol : nil
        enterView.label = composition.isEmpty ? "" : "確定"
    }
}
