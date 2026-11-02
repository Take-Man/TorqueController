import AppKit
import TorqueEngine

/// フリックパネル。ガイド、入力欄、変換を持ち、キーの操作を入力に変える。
@MainActor
final class FlickPanel {
    /// パネルの重なり順。同じレベルだとクリックしたパネルが前面に来るので、レベルで固定する。
    private enum Levels {
        static let panel = NSWindow.Level.statusBar
        static let composition = NSWindow.Level(rawValue: panel.rawValue + 1)
        static let overlay = NSWindow.Level(rawValue: panel.rawValue + 2)
        static let guide = NSWindow.Level(rawValue: panel.rawValue + 3)
    }

    private enum Metrics {
        static let keySide: CGFloat = 56
        static let sideKeyWidth: CGFloat = 44
        static let gap: CGFloat = 6
        static let padding: CGFloat = 8
        static let rows = 4
        static let gridColumns = 3
        /// ガイドの下の区画の文字が画面の下端で切れないよう、パネルを画面下端から離す距離。
        static let minScreenBottomMargin: CGFloat = 60
        static let screenMargin: CGFloat = 16
        /// スコープの文字列と中心の円の間の余白。
        static let scopePadding: CGFloat = 6
        static let minScopeRadius: CGFloat = 26
        /// 候補の上にカーソルがあるかを調べる間隔。
        static let cursorTrackingInterval: TimeInterval = 0.03
        static let modeSlideDuration: TimeInterval = 0.18
        static let compositionToggleDuration: TimeInterval = 0.2
    }

    /// 持ち手で動かし終えたとき。
    var onMoved: ((NSPoint) -> Void)?
    /// 持ち手をクリックしたとき。
    var onGripClicked: ((NSView) -> Void)?
    /// 持ち手で動かせる範囲の制限。
    var constrain: ((NSPoint) -> NSPoint)?
    /// 候補が隠れるときに左右反転する。
    var mirrorsCandidates = true {
        didSet { showSession() }
    }

    let panel: FloatingPanel
    private let logicalSize: NSSize
    private var scale: CGFloat = 1
    private let guidePanel: FloatingPanel
    private let guideView = FlickGuideView()
    private let compositionPanel: FloatingPanel
    private let compositionView = CompositionView()
    private var gridViews: [KeyView] = []
    private var modeViews: [InputMode: KeyView] = [:]
    private let modeBackgroundView = ModeBackgroundView()
    private let modeHighlightView = NSView()
    private let deleteView = KeyView(symbolName: FlickPanel.deleteSymbol)
    private let spaceView = KeyView(symbolName: FlickPanel.spaceSymbol)
    private let enterView = KeyView(symbolName: FlickPanel.enterSymbol)

    private static let deleteSymbol = "delete.left"
    private static let clearSymbol = "trash"
    private static let spaceSymbol = "space"
    private static let convertSymbol = "arrow.triangle.2.circlepath"
    private static let enterSymbol = "return"
    private static let sendSymbol = "paperplane"

    private var composition = Composition()
    private var mode = InputMode.kana
    private var shift = LatchState.off
    private var isEnabled = true
    /// パスワード欄にフォーカスがある間は、入力欄に平文を出さず対象アプリへ直接送り、学習にも記録しない。
    private(set) var isSecureFocused = false
    /// パスワード欄に入るときに、かなから自動で切り替えたか。抜けるときに戻す。
    private var switchedFromKana = false
    /// 対象アプリへの送信。テストで差し替える。
    var sendText: (String) -> Void = { TextSender.send($0) }
    var sendKey: (TextSender.Key) -> Void = { TextSender.send($0) }
    /// 入力欄の文字列。
    var fieldText: String { composition.text }

    private var converter: Converter?
    private let learningURL: URL
    private let overlayPanel: FloatingPanel
    private let overlayView = CandidateOverlayView()
    /// 変換中の状態。変換していないときは nil。
    private var session: ConversionSession?
    private var cursorTimer: Timer?

    private var deleteRepeatTimer: Timer?
    /// 長押しで1文字でも消したら、離したときのクリックとして扱わない。
    private var deleteHasRepeated = false
    /// 全削除の位置まで一度でも動かしたら、離したときのクリックとして扱わない。
    private var deleteHasDragged = false
    private var isConverting: Bool { session != nil }

    /// 今の入力モードとシフトの状態で表示するキー。
    private var grid: [GridKey] {
        shift == .off ? mode.grid : mode.grid.map(\.uppercased)
    }

    /// origin はパネルの左下。
    init(origin: NSPoint, converter: Converter?, learningURL: URL) {
        self.converter = converter
        self.learningURL = learningURL
        overlayPanel = FloatingPanel(contentRect: NSScreen.main?.frame ?? .zero)
        overlayPanel.level = Levels.overlay
        overlayPanel.hasShadow = false
        overlayPanel.contentView = overlayView
        let gridHeight = CGFloat(Metrics.rows) * Metrics.keySide + CGFloat(Metrics.rows - 1) * Metrics.gap
        let contentWidth = Metrics.sideKeyWidth * 2 + CGFloat(Metrics.gridColumns) * Metrics.keySide + CGFloat(Metrics.gridColumns + 1) * Metrics.gap
        let size = NSSize(
            width: contentWidth + Metrics.padding * 2,
            height: gridHeight + Metrics.padding * 2
        )
        logicalSize = size
        panel = FloatingPanel(contentRect: NSRect(origin: origin, size: size))
        panel.level = Levels.panel

        guidePanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.guideSide, height: Self.guideSide))
        guidePanel.level = Levels.guide
        guidePanel.ignoresMouseEvents = true
        guidePanel.contentView = guideView

        let background = PanelBackgroundView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = background

        compositionPanel = FloatingPanel(contentRect: .zero)
        compositionPanel.level = Levels.composition
        compositionPanel.hasShadow = false
        compositionPanel.contentView = compositionView
        compositionView.maxFieldWidth = size.width - CompositionView.margin * 2
        compositionView.onClick = { [weak self] in self?.compositionClicked() }
        compositionView.onExpandChange = { [weak self] isExpanded in
            self?.compositionView.isExpanded = isExpanded
            self?.animateCompositionPanel()
        }
        overlayView.onRegionClicked = { [weak self] region in self?.overlayClicked(region) }

        layoutGrid(in: background, gridHeight: gridHeight)
        layoutSideColumns(in: background, gridHeight: gridHeight)
        applyMode()
    }

    func show() {
        panel.orderFrontRegardless()
        showSession()
    }

    /// 隠すときは変換を抜ける。入力欄の文字は残り、次に表示したときに戻る。
    func hide() {
        finishConversion()
        panel.orderOut(nil)
        compositionPanel.orderOut(nil)
    }

    func setPlacement(origin: NSPoint, scale: CGFloat) {
        self.scale = scale
        panel.place(origin: origin, logicalSize: logicalSize, scale: scale)
        let side = Self.guideSide
        guidePanel.place(origin: .zero, logicalSize: NSSize(width: side, height: side), scale: scale)
        showSession()
    }

    func setVisible(_ isVisible: Bool) {
        guard isVisible != panel.isVisible else { return }
        if isVisible {
            show()
        } else {
            hide()
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        applyEnabled()
    }

    /// パスワード欄に入ったら変換を抜け、かななら ABC に切り替える。入力欄に残っている文字は送らず、そのまま残す。
    /// 抜けたら通常の挙動に戻す。
    func setSecureFocused(_ isSecureFocused: Bool) {
        guard isSecureFocused != self.isSecureFocused else { return }
        self.isSecureFocused = isSecureFocused
        if isSecureFocused {
            finishConversion()
            if mode == .kana {
                mode = .latin
                switchedFromKana = true
            }
        } else if switchedFromKana {
            mode = .kana
            switchedFromKana = false
        }
        shift = .off
        applyMode()
        applyEnabled()
        compositionChanged()
    }

    /// 変換中は、文字のキーと切替キーを無効にして明度を下げる。
    private func applyEnabled() {
        for view in gridViews + Array(modeViews.values) {
            view.isEnabled = isEnabled && !isConverting
            view.isDimmed = isConverting
        }
        if isSecureFocused, let kanaView = modeViews[.kana] {
            kanaView.isEnabled = false
            kanaView.isDimmed = true
        }
        modeBackgroundView.isDimmed = isConverting
        modeHighlightView.alphaValue = isConverting ? KeyView.dimmedAlpha : 1
        for view in [deleteView, spaceView, enterView] {
            view.isEnabled = isEnabled
        }
        deleteView.keepsPressedOutside = !isConverting
        deleteView.symbolName = isConverting ? CandidateOverlayView.backSymbol : Self.deleteSymbol
    }

    /// パネルと、キーから出すガイドと、1行の入力欄の全体の範囲。パネルの左下が原点で、倍率をかける前の大きさ。
    var logicalExtent: CGRect {
        var extent = CGRect(origin: .zero, size: logicalSize)
        let radius = FlickGuideView.outerRadius
        for view in gridViews {
            extent = extent.union(CGRect(x: view.frame.midX - radius, y: view.frame.midY - radius, width: radius * 2, height: radius * 2))
        }
        extent.size.height = max(extent.maxY, logicalSize.height + CompositionView.collapsedPanelHeight - CompositionView.overlap) - extent.minY
        return extent
    }

    private static var guideSide: CGFloat {
        (FlickGuideView.outerRadius + 2) * 2
    }

    static var panelWidth: CGFloat {
        Metrics.sideKeyWidth * 2 + CGFloat(Metrics.gridColumns) * Metrics.keySide + CGFloat(Metrics.gridColumns + 1) * Metrics.gap + Metrics.padding * 2
    }

    static var panelHeight: CGFloat {
        CGFloat(Metrics.rows) * Metrics.keySide + CGFloat(Metrics.rows - 1) * Metrics.gap + Metrics.padding * 2
    }

    /// 全パネルの左下の初期位置。
    static func initialOrigin() -> NSPoint {
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

        modeBackgroundView.frame = background.bounds
        modeBackgroundView.keyFrames = InputMode.allCases.indices.map { frame(x: leftX, position: $0) }
        background.addSubview(modeBackgroundView)
        modeHighlightView.wantsLayer = true
        modeHighlightView.layer?.cornerRadius = 8
        modeHighlightView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        modeHighlightView.frame = frame(x: leftX, position: 0)
        background.addSubview(modeHighlightView)

        for (position, mode) in InputMode.allCases.enumerated() {
            let view = KeyView(label: mode.label)
            view.fillsBackground = false
            view.frame = frame(x: leftX, position: position)
            view.onEnd = { [weak self] _, isInside in
                if isInside {
                    self?.switchMode(to: mode)
                }
            }
            background.addSubview(view)
            modeViews[mode] = view
        }

        // 削除キーは正方形で枠の下にそろえ、上の余白に持ち手を置く
        let deleteSlot = frame(x: rightX, position: 0)
        deleteView.frame = NSRect(x: deleteSlot.minX, y: deleteSlot.minY, width: Metrics.sideKeyWidth, height: Metrics.sideKeyWidth)
        let grip = GripView(frame: NSRect(
            x: deleteSlot.minX,
            y: deleteView.frame.maxY,
            width: Metrics.sideKeyWidth,
            height: deleteSlot.maxY - deleteView.frame.maxY
        ))
        grip.onDrag = { [weak self] in self?.showSession() }
        grip.onEnd = { [weak self] origin in self?.onMoved?(origin) }
        grip.onClick = { [weak self] view in self?.onGripClicked?(view) }
        grip.constrain = { [weak self] origin in self?.constrain?(origin) ?? origin }
        background.addSubview(grip)
        deleteView.onBegin = { [weak self] _ in self?.deleteBegan() }
        deleteView.onDrag = { [weak self] offset in self?.deleteDragged(offset) }
        deleteView.onEnd = { [weak self] offset, isInside in self?.deleteEnded(offset, isInside: isInside) }
        background.addSubview(deleteView)

        let actions: [(KeyView, @MainActor () -> Void)] = [
            (spaceView, { [weak self] in self?.spacePressed() }),
            (enterView, { [weak self] in self?.enterPressed() }),
        ]
        for (position, (view, action)) in actions.enumerated() {
            view.frame = frame(x: rightX, position: position + 1)
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
                view.symbolName = shift.shiftSymbol
                view.isSelected = shift != .off
            case .cycle:
                break
            }
        }
        for (mode, view) in modeViews {
            view.isSelected = mode == self.mode
        }
        if let target = modeViews[mode]?.frame, modeHighlightView.frame != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.modeSlideDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                modeHighlightView.animator().frame = target
            }
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
        guideView.direction = FlickDirection.from(offset: normalized(offset), deadZone: FlickGuideView.innerRadius)
    }

    /// 画面上の移動量を、倍率をかける前の大きさに直す。
    private func normalized(_ offset: CGVector) -> CGVector {
        CGVector(dx: offset.dx / scale, dy: offset.dy / scale)
    }

    private func gridKeyEnded(_ index: Int, offset: CGVector, isInside: Bool) {
        switch grid[index] {
        case .flick(let characters):
            guidePanel.orderOut(nil)
            let direction = FlickDirection.from(offset: normalized(offset), deadZone: FlickGuideView.innerRadius)
            if let character = characters.character(in: direction) {
                if isSecureFocused {
                    sendText(character)
                } else if mode == .kana {
                    composition.appendPending(character)
                } else {
                    composition.appendConfirmed(character)
                }
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

    /// 数字記号と英字には変換がないので、切り替えた時点で未確定のかなをかなのまま確定にする。
    private func switchMode(to mode: InputMode) {
        self.mode = mode
        shift = .off
        switchedFromKana = false
        // パスワード欄では入力欄を使わないので、残っている文字はそのままにする
        if mode != .kana, !isSecureFocused {
            composition.confirmPending()
            compositionChanged()
        }
        applyMode()
    }

    /// 入力欄に文字があれば末尾を消し、なければ対象アプリへ Delete キーを送る。
    private func deleteOne() {
        if composition.isEmpty || isSecureFocused {
            sendKey(.delete)
        } else {
            composition.deleteLast()
            compositionChanged()
        }
    }

    /// 長押しの連続削除を準備する。欄の文字から始めたら、欄が空になった時点で止めて、対象アプリの文字までは消さない。
    private func deleteBegan() {
        guard !isConverting else { return }
        deleteHasRepeated = false
        deleteHasDragged = false
        let startedWithText = !composition.isEmpty && !isSecureFocused
        let timer = Timer(
            fire: Date().addingTimeInterval(DeleteGesture.repeatDelay),
            interval: DeleteGesture.repeatInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 離すイベントを受け取れなかったときも、押し続けの状態を残さない
                guard NSEvent.pressedMouseButtons & 1 != 0, !(startedWithText && self.composition.isEmpty) else {
                    self.stopDeleteRepeat()
                    return
                }
                self.deleteHasRepeated = true
                self.deleteOne()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deleteRepeatTimer = timer
    }

    private func deleteDragged(_ offset: CGVector) {
        guard !isConverting else { return }
        let isClear = DeleteGesture.isClear(offset: normalized(offset)) && !composition.isEmpty && !isSecureFocused
        if isClear {
            deleteHasDragged = true
            stopDeleteRepeat()
        }
        deleteView.symbolName = isClear ? Self.clearSymbol : Self.deleteSymbol
    }

    /// 変換中はクリックだけを受け、戻す領域と同じ働きをする。
    private func deleteEnded(_ offset: CGVector, isInside: Bool) {
        stopDeleteRepeat()
        if isConverting {
            if isInside {
                overlayClicked(.back)
            }
            return
        }
        deleteView.symbolName = Self.deleteSymbol
        if DeleteGesture.isClear(offset: normalized(offset)) {
            guard !isSecureFocused else { return }
            composition.clear()
            compositionChanged()
        } else if isInside, !deleteHasRepeated, !deleteHasDragged {
            deleteOne()
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    /// 変換中なら変換を抜ける。未確定のかながあれば変換を始める。入力欄に文字があるときの空白は、順序を保つため欄に入れる。
    private func spacePressed() {
        if isConverting {
            finishConversion()
        } else if isSecureFocused {
            sendText(" ")
        } else if !composition.pending.isEmpty {
            startConversion()
        } else if composition.isEmpty {
            sendText(" ")
        } else {
            composition.appendConfirmed(" ")
            compositionChanged()
        }
    }

    private func enterPressed() {
        finishConversion()
        if composition.isEmpty || isSecureFocused {
            sendKey(.enter)
        } else {
            sendComposition()
        }
    }

    private func sendComposition() {
        sendText(composition.text)
        composition.clear()
        compositionChanged()
    }

    private func compositionChanged() {
        enterView.symbolName = composition.isEmpty || isSecureFocused ? Self.enterSymbol : Self.sendSymbol
        spaceView.symbolName = composition.pending.isEmpty || isSecureFocused ? Self.spaceSymbol : Self.convertSymbol
        showSession()
    }

    // MARK: - 変換

    private func startConversion() {
        guard let converter, !composition.pending.isEmpty, !isSecureFocused else { return }
        session = ConversionSession(reading: composition.pending) { converter.columns(for: $0) }
        applyEnabled()
        showSession(animated: true)
        cursorTimer = Timer.scheduledTimer(withTimeInterval: Metrics.cursorTrackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackCursor() }
        }
    }

    /// 変換を抜ける。選んだ分は確定にして残し、残りの読みは未確定のかなに戻す。
    private func finishConversion() {
        guard let session else { return }
        composition.applyConversion(converted: session.convertedText, remaining: session.remaining)
        recordLearning(session.selections)
        self.session = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
        applyEnabled()
        compositionChanged()
    }

    private func recordLearning(_ selections: [ConversionSession.Selection]) {
        guard !selections.isEmpty, !isSecureFocused else { return }
        for selection in selections {
            converter?.learning.record(reading: selection.reading, surface: selection.surface)
        }
        do {
            try converter?.learning.save(to: learningURL)
        } catch {
            NSLog("学習を保存できません: %@", String(describing: error))
        }
    }

    private func compositionClicked() {
        if isConverting {
            finishConversion()
        } else {
            startConversion()
        }
    }

    private func overlayClicked(_ region: CandidateLayout.Region) {
        guard var session else { return }
        var animated = true
        switch region {
        case .candidate(let column, let row):
            let candidates = Array(session.visibleCandidates(column: column))
            session.select(column: column, candidate: candidates[row])
        case .next(let column):
            session.nextPage(column: column)
            animated = false
        case .center:
            finishConversion()
            return
        case .back:
            guard session.undo() else {
                finishConversion()
                return
            }
        }
        self.session = session
        if session.isFinished {
            finishConversion()
            sendComposition()
        } else {
            showSession(animated: animated)
        }
    }

    /// 候補や中心の上でだけクリックを受け、それ以外は下のキーやアプリへ通す。
    private func trackCursor() {
        let location = NSEvent.mouseLocation
        let point = CGPoint(x: (location.x - overlayPanel.frame.minX) / scale, y: (location.y - overlayPanel.frame.minY) / scale)
        overlayPanel.ignoresMouseEvents = overlayView.trackCursor(at: point) == nil
    }

    /// 入力欄の表示と、候補の重ね表示を今の状態に合わせる。
    private func showSession(animated: Bool = false) {
        compositionView.confirmedText = composition.confirmed + (session?.convertedText ?? "")
        compositionView.pendingText = session?.remaining ?? composition.pending
        compositionView.underlinesPending = isConverting
        showCompositionPanel()
        guard let session, let reading = session.columns.first?.reading else {
            overlayPanel.orderOut(nil)
            return
        }

        if let screen = panel.screen ?? NSScreen.main {
            overlayPanel.setFrame(screen.frame, display: false)
            overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
            overlayView.setBoundsSize(NSSize(width: screen.frame.width / scale, height: screen.frame.height / scale))
        }
        let scope = overlayRect(of: compositionView, rect: compositionView.pendingRect(count: reading.count))
        overlayView.update(
            session: session,
            center: CGPoint(x: scope.midX, y: scope.midY),
            scopeRadius: max(Metrics.minScopeRadius, hypot(scope.width, scope.height) / 2 + Metrics.scopePadding),
            allowsMirroring: mirrorsCandidates,
            animated: animated
        )
        overlayPanel.orderFrontRegardless()
        trackCursor()
    }

    /// 入力欄は文字があるときだけ、文字の背景となる最小の幅で、パネルの上に左揃えで出す。
    private func showCompositionPanel() {
        guard !composition.isEmpty || isConverting else {
            compositionView.isExpanded = false
            compositionPanel.orderOut(nil)
            return
        }
        guard panel.isVisible else { return }
        compositionPanel.place(origin: compositionPanelOrigin, logicalSize: compositionLogicalSize, scale: scale)
        compositionPanel.orderFrontRegardless()
    }

    private var compositionLogicalSize: NSSize {
        compositionView.fittingSize()
    }

    private var compositionPanelOrigin: NSPoint {
        NSPoint(x: panel.frame.minX, y: panel.frame.maxY - CompositionView.overlap * scale)
    }

    private var compositionPanelFrame: NSRect {
        let size = compositionLogicalSize
        return NSRect(origin: compositionPanelOrigin, size: NSSize(width: size.width * scale, height: size.height * scale))
    }

    /// 開閉のマークのクリックで、入力欄をなめらかに開閉する。候補の位置は開閉が終わってから合わせる。
    private func animateCompositionPanel() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.compositionToggleDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            compositionPanel.animator().setFrame(compositionPanelFrame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.showSession() }
        }
    }

    /// パネルの中の範囲を、重ね表示の座標に変換する。
    private func overlayRect(of view: NSView, rect: CGRect) -> CGRect {
        let inWindow = view.convert(rect, to: nil)
        let onScreen = (view.window ?? panel).convertToScreen(inWindow)
        let offset = onScreen.offsetBy(dx: -overlayPanel.frame.minX, dy: -overlayPanel.frame.minY)
        return CGRect(x: offset.minX / scale, y: offset.minY / scale, width: offset.width / scale, height: offset.height / scale)
    }
}
