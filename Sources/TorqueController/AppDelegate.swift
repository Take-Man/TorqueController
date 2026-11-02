import AppKit
import TorqueEngine

/// 倍率と不透明度のメニュー項目が持つ値。
private final class PanelChoice {
    let panel: PanelID
    let value: CGFloat

    init(panel: PanelID, value: CGFloat) {
        self.panel = panel
        self.value = value
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private static let keyboardGap: CGFloat = 6
    /// QWERTY の下に、入力欄を置く分だけ空ける。
    private static let qwertyLift: CGFloat = 56
    private var flickPanel: FlickPanel?
    private var compactPanel: CompactPanel?
    private var permissionTimer: Timer?
    private let focusMonitor = FocusMonitor()
    private var focusPolicy = FocusPolicy()
    private static let autoShowKey = "flickAutoShow"
    private static let autoHideKey = "flickAutoHide"
    private static let electronKey = "enableElectronApps"
    private var isDictionaryLoaded = false
    private let settings: PanelSettings
    private let cornerMonitor = CornerMonitor()
    private var arePanelsVisible = true

    init(settings: PanelSettings = PanelSettings(defaults: .standard)) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        FloatingPanel.onRightClick = { [weak self] event, view in self?.showAppMenu(event, in: view) }

        focusPolicy.autoShow = UserDefaults.standard.object(forKey: Self.autoShowKey) as? Bool ?? true
        focusPolicy.autoHide = UserDefaults.standard.bool(forKey: Self.autoHideKey)

        let origin = FlickPanel.initialOrigin()
        let flickPanel = FlickPanel(
            origin: NSPoint(x: origin.x + CompactPanel.width + Self.keyboardGap, y: origin.y),
            converter: loadConverter(),
            learningURL: LearningModel.defaultURL
        )
        flickPanel.onMoved = { [weak self] origin in self?.settings.setOrigin(origin, of: .flick) }
        flickPanel.onGripClicked = { [weak self] view in self?.showPanelMenu(for: .flick, from: view) }
        flickPanel.constrain = { [weak self] origin in self?.constrained(origin, of: .flick) ?? origin }
        flickPanel.mirrorsCandidates = settings.mirrorsCandidates
        flickPanel.show()
        self.flickPanel = flickPanel

        let compactPanel = CompactPanel(
            origin: origin,
            qwertyOrigin: NSPoint(x: origin.x, y: origin.y + FlickPanel.panelHeight + Self.qwertyLift),
            shortcuts: ShortcutStore.load(from: ShortcutStore.defaultURL)
        )
        compactPanel.onToggleFlick = { [weak self] in
            self?.focusPolicy.userToggledFlick()
            self?.applyFocusPolicy()
        }
        compactPanel.onMoved = { [weak self] panel, origin in self?.settings.setOrigin(origin, of: panel) }
        compactPanel.onGripClicked = { [weak self] panel, view in self?.showPanelMenu(for: panel, from: view) }
        compactPanel.constrain = { [weak self] panel, origin in self?.constrained(origin, of: panel) ?? origin }
        compactPanel.show()
        self.compactPanel = compactPanel
        applyLayout()
        applyOpacity()
        applyFocusPolicy()

        cornerMonitor.corners = settings.corners
        cornerMonitor.dwellDuration = settings.dwell
        cornerMonitor.onTrigger = { [weak self] in self?.togglePanels() }
        cornerMonitor.start()
        noticeHotCornerConflictOnce()

        focusMonitor.onObserve = { [weak self] kind, elementChanged in
            guard let self, self.focusPolicy.observe(kind: kind, elementChanged: elementChanged) else { return }
            self.applyFocusPolicy()
        }
        focusMonitor.enablesElectronApps = UserDefaults.standard.object(forKey: Self.electronKey) as? Bool ?? true
        focusMonitor.start()

        // 未許可なら、初回だけ macOS の許可ダイアログを出す
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionState()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.refreshPermissionState()
            }
        }
    }

    private func applyFocusPolicy() {
        let isSecure = focusPolicy.kind == .secure
        // 隠すときの変換の終了で記録しないよう、先に切り替える
        flickPanel?.setSecureFocused(isSecure)
        flickPanel?.setVisible(arePanelsVisible && focusPolicy.flickVisible)
        compactPanel?.setFlickVisible(focusPolicy.flickVisible)
        compactPanel?.setSecureFocused(isSecure)
    }

    /// 保存した位置と倍率でパネルを置く。動かしていないパネルは、倍率に合わせた初期位置に置く。
    private func applyLayout() {
        guard let compactPanel, let flickPanel else { return }
        let base = FlickPanel.initialOrigin()
        let screens = NSScreen.screens.map(\.frame)

        func origin(_ panel: PanelID, size: NSSize, fallback: NSPoint) -> NSPoint {
            let scale = settings.scale(of: panel)
            var result = fallback
            if let saved = settings.origin(of: panel) {
                let frame = NSRect(origin: saved, size: NSSize(width: size.width * scale, height: size.height * scale))
                if PanelSettings.isReachable(frame, screens: screens) {
                    result = saved
                }
            }
            return constrained(result, of: panel)
        }

        let compactScale = settings.scale(of: .compact)
        let flickScale = settings.scale(of: .flick)
        let compactOrigin = origin(.compact, size: NSSize(width: CompactPanel.width, height: CompactPanel.height), fallback: base)
        compactPanel.setPlacement(origin: compactOrigin, scale: compactScale)

        let flickOrigin = origin(
            .flick,
            size: NSSize(width: FlickPanel.panelWidth, height: FlickPanel.panelHeight),
            fallback: NSPoint(x: compactOrigin.x + CompactPanel.width * compactScale + Self.keyboardGap, y: compactOrigin.y)
        )
        flickPanel.setPlacement(origin: flickOrigin, scale: flickScale)

        let top = max(compactOrigin.y + CompactPanel.height * compactScale, flickOrigin.y + FlickPanel.panelHeight * flickScale)
        let qwertyOrigin = origin(
            .qwerty,
            size: compactPanel.qwertyLogicalSize,
            fallback: NSPoint(x: compactOrigin.x, y: top + Self.qwertyLift * flickScale)
        )
        compactPanel.setQwertyPlacement(origin: qwertyOrigin, scale: settings.scale(of: .qwerty))
    }

    /// 設定が有効なら、パネルとガイドが画面に収まる位置に直す。
    private func constrained(_ origin: NSPoint, of panel: PanelID) -> NSPoint {
        guard settings.keepsInScreen, let compactPanel, let flickPanel else { return origin }
        let scale = settings.scale(of: panel)
        let logical: CGRect
        switch panel {
        case .compact: logical = compactPanel.logicalExtent
        case .flick: logical = flickPanel.logicalExtent
        case .qwerty: logical = CGRect(origin: .zero, size: compactPanel.qwertyLogicalSize)
        }
        let extent = CGRect(x: logical.minX * scale, y: logical.minY * scale, width: logical.width * scale, height: logical.height * scale)
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        guard let bounds = screen?.frame else { return origin }
        return PanelSettings.clampedOrigin(origin, extent: extent, bounds: bounds)
    }

    private func applyOpacity() {
        compactPanel?.setOpacity(settings.opacity(of: .compact))
        compactPanel?.qwerty.setOpacity(settings.opacity(of: .qwerty))
        flickPanel?.setOpacity(settings.opacity(of: .flick))
    }

    private func showPanelMenu(for panel: PanelID, from view: NSView) {
        makePanelMenu(for: panel).popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
    }

    /// 持ち手のクリックで開く、そのパネル専用のメニュー。
    func makePanelMenu(for panel: PanelID) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeOpacityItem("不透明度", for: panel))
        menu.addItem(makeScaleItem("倍率", for: panel))
        return menu
    }

    /// メニューバーのアイコンが隠れていても、右クリックから同じメニューを使えるようにする。
    private func showAppMenu(_ event: NSEvent, in view: NSView) {
        makeAppMenu().popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
    }

    /// メニューバーと同じ、アプリ全体のメニュー。
    func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuNeedsUpdate(menu)
        return menu
    }

    private func makeScaleItem(_ title: String, for panel: PanelID) -> NSMenuItem {
        makeSubmenu(title, PanelSettings.scaleChoices.map { value in
            (Self.percent(value), PanelChoice(panel: panel, value: value), settings.scale(of: panel) == value)
        }, action: #selector(selectScale(_:)))
    }

    private func makeOpacityItem(_ title: String, for panel: PanelID) -> NSMenuItem {
        makeSubmenu(title, PanelSettings.opacityChoices.map { value in
            (Self.percent(value), PanelChoice(panel: panel, value: value), settings.opacity(of: panel) == value)
        }, action: #selector(selectOpacity(_:)))
    }

    /// パネルごとの項目を、1つの階層にまとめる。
    private func makePerPanelItem(_ title: String, _ makeItem: (String, PanelID) -> NSMenuItem) -> NSMenuItem {
        let submenu = NSMenu()
        for (panel, name) in [(PanelID.compact, "コンパクト"), (.flick, "フリック"), (.qwerty, "QWERTY")] {
            submenu.addItem(makeItem(name, panel))
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private static func percent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func togglePanels() {
        arePanelsVisible.toggle()
        compactPanel?.setPanelsVisible(arePanelsVisible)
        applyFocusPolicy()
    }

    /// macOS のホットコーナーと同じ隅だと両方が反応するので、初回に一度だけ案内する。
    private func noticeHotCornerConflictOnce() {
        guard !settings.hotCornerNoticeShown else { return }
        settings.hotCornerNoticeShown = true
        let dock = UserDefaults(suiteName: "com.apple.dock")
        // 値が 1 以下なら、その隅に動作は割り当てられていない
        let conflicts = settings.corners.filter { (dock?.integer(forKey: $0.hotCornerKey) ?? 0) > 1 }
        guard !conflicts.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "ホットコーナーと重なっています"
        let names = conflicts.map(\.label).joined(separator: "、")
        alert.informativeText = "\(names)の隅には macOS のホットコーナーが設定されています。隅にカーソルを置くと両方が反応します。TorqueController のメニューの「オン/オフの隅」か、システム設定のホットコーナーで、別の隅に変えてください。"
        NSApp.activate()
        alert.runModal()
    }

    private func loadConverter() -> Converter? {
        guard let url = Bundle.main.url(forResource: "torque", withExtension: "dict"),
              let dictionary = try? TorqueDictionary(contentsOf: url)
        else { return nil }
        isDictionaryLoaded = true
        return Converter(dictionary: dictionary, learning: loadLearning())
    }

    /// 壊れた学習ファイルは上書きせず、別名で残して空から始める。
    private func loadLearning() -> LearningModel {
        let url = LearningModel.defaultURL
        guard FileManager.default.fileExists(atPath: url.path) else { return LearningModel() }
        do {
            return try LearningModel.load(from: url)
        } catch {
            NSLog("学習ファイルを読めません: %@", String(describing: error))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("broken"))
            return LearningModel()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AXIsProcessTrusted()
        addInfoItem(to: menu, "アクセシビリティ: \(trusted ? "許可済み" : "未許可")")
        addInfoItem(to: menu, "辞書: \(isDictionaryLoaded ? "読み込み済み" : "読み込めません(変換は使えません)")")
        menu.addItem(.separator())
        addActionItem(to: menu, "フリックパネルを自動で表示", #selector(toggleAutoShow)).state = focusPolicy.autoShow ? .on : .off
        addActionItem(to: menu, "フリックパネルを自動で隠す", #selector(toggleAutoHide)).state = focusPolicy.autoHide ? .on : .off
        addActionItem(to: menu, "Electron アプリの入力欄も判定する", #selector(toggleElectronApps)).state = focusMonitor.enablesElectronApps ? .on : .off
        menu.addItem(.separator())
        addActionItem(to: menu, arePanelsVisible ? "全パネルを隠す" : "全パネルを表示", #selector(togglePanelsFromMenu))
        menu.addItem(makeSubmenu("オン/オフの隅", ScreenCorner.allCases.map { corner in
            (corner.label, corner.rawValue, settings.corners.contains(corner))
        }, action: #selector(toggleCorner(_:))))
        menu.addItem(makeSubmenu("隅に置く時間", PanelSettings.dwellChoices.map { value in
            ("\(value) 秒", value, settings.dwell == value)
        }, action: #selector(selectDwell(_:))))
        menu.addItem(makePerPanelItem("パネルの倍率を変更", makeScaleItem(_:for:)))
        menu.addItem(makePerPanelItem("パネルの不透明度を変更", makeOpacityItem(_:for:)))
        addActionItem(to: menu, "パネルとガイドを画面内に収める", #selector(toggleKeepsInScreen)).state = settings.keepsInScreen ? .on : .off
        addActionItem(to: menu, "候補が隠れるときに左右反転する", #selector(toggleMirrorsCandidates)).state = settings.mirrorsCandidates ? .on : .off
        addActionItem(to: menu, "パネルの位置を初期に戻す", #selector(resetPositions))
        menu.addItem(.separator())
        addActionItem(to: menu, "ショートカットの設定を開く…", #selector(openShortcutSettings))
        addActionItem(to: menu, "ショートカットの設定を読み直す", #selector(reloadShortcutSettings))
        menu.addItem(.separator())
        if !trusted {
            let settings = NSMenuItem(title: "システム設定を開く…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(settings)
        }
        let quit = NSMenuItem(title: "TorqueController を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @discardableResult
    private func addActionItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func makeSubmenu(_ title: String, _ items: [(String, Any, Bool)], action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        for (label, value, isOn) in items {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = isOn ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    @objc private func togglePanelsFromMenu() {
        togglePanels()
    }

    @objc private func toggleCorner(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let corner = ScreenCorner(rawValue: name) else { return }
        var corners = settings.corners
        if corners.contains(corner) {
            corners.remove(corner)
        } else {
            corners.insert(corner)
        }
        settings.corners = corners
        cornerMonitor.corners = corners
    }

    @objc private func selectDwell(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? TimeInterval else { return }
        settings.dwell = value
        cornerMonitor.dwellDuration = value
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PanelChoice else { return }
        settings.setScale(choice.value, of: choice.panel)
        applyLayout()
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PanelChoice else { return }
        settings.setOpacity(choice.value, of: choice.panel)
        applyOpacity()
    }

    @objc private func toggleKeepsInScreen() {
        settings.keepsInScreen.toggle()
        applyLayout()
    }

    @objc private func toggleMirrorsCandidates() {
        settings.mirrorsCandidates.toggle()
        flickPanel?.mirrorsCandidates = settings.mirrorsCandidates
    }

    @objc private func resetPositions() {
        for panel in PanelID.allCases {
            settings.setOrigin(nil, of: panel)
        }
        applyLayout()
    }

    @objc private func toggleAutoShow() {
        focusPolicy.autoShow.toggle()
        UserDefaults.standard.set(focusPolicy.autoShow, forKey: Self.autoShowKey)
    }

    @objc private func toggleAutoHide() {
        focusPolicy.autoHide.toggle()
        UserDefaults.standard.set(focusPolicy.autoHide, forKey: Self.autoHideKey)
    }

    @objc private func toggleElectronApps() {
        focusMonitor.enablesElectronApps.toggle()
        UserDefaults.standard.set(focusMonitor.enablesElectronApps, forKey: Self.electronKey)
    }

    @objc private func openShortcutSettings() {
        _ = ShortcutStore.load(from: ShortcutStore.defaultURL)
        NSWorkspace.shared.open(ShortcutStore.defaultURL)
    }

    @objc private func reloadShortcutSettings() {
        compactPanel?.setShortcuts(ShortcutStore.load(from: ShortcutStore.defaultURL))
    }

    private func addInfoItem(to menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        flickPanel?.setEnabled(trusted)
        compactPanel?.setEnabled(trusted)
        let symbol = trusted ? "flickPanel" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TorqueController")
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
