import AppKit
import TorqueEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private static let keyboardGap: CGFloat = 6
    /// QWERTY の下に、入力欄を置く分だけ空ける。
    private static let qwertyLift: CGFloat = 56
    private var keyboard: FlickKeyboard?
    private var compact: CompactKeyboard?
    private var permissionTimer: Timer?
    private let focusMonitor = FocusMonitor()
    private var focusPolicy = FocusPolicy()
    private static let autoShowKey = "flickAutoShow"
    private static let autoHideKey = "flickAutoHide"
    private var isDictionaryLoaded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        focusPolicy.autoShow = UserDefaults.standard.object(forKey: Self.autoShowKey) as? Bool ?? true
        focusPolicy.autoHide = UserDefaults.standard.bool(forKey: Self.autoHideKey)

        let origin = FlickKeyboard.initialOrigin()
        let keyboard = FlickKeyboard(
            origin: NSPoint(x: origin.x + CompactKeyboard.width + Self.keyboardGap, y: origin.y),
            converter: loadConverter(),
            learningURL: LearningModel.defaultURL
        )
        keyboard.show()
        self.keyboard = keyboard

        let compact = CompactKeyboard(
            origin: origin,
            qwertyOrigin: NSPoint(x: origin.x, y: origin.y + FlickKeyboard.panelHeight + Self.qwertyLift),
            shortcuts: ShortcutStore.load(from: ShortcutStore.defaultURL)
        )
        compact.onToggleFlick = { [weak self] in
            self?.focusPolicy.userToggledFlick()
            self?.applyFocusPolicy()
        }
        compact.show()
        self.compact = compact
        applyFocusPolicy()

        focusMonitor.onObserve = { [weak self] kind, elementChanged in
            guard let self, self.focusPolicy.observe(kind: kind, elementChanged: elementChanged) else { return }
            self.applyFocusPolicy()
        }
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
        keyboard?.isLearningEnabled = !isSecure
        keyboard?.setVisible(focusPolicy.flickVisible)
        compact?.setFlickVisible(focusPolicy.flickVisible)
        compact?.setSecureFocused(isSecure)
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

    @objc private func toggleAutoShow() {
        focusPolicy.autoShow.toggle()
        UserDefaults.standard.set(focusPolicy.autoShow, forKey: Self.autoShowKey)
    }

    @objc private func toggleAutoHide() {
        focusPolicy.autoHide.toggle()
        UserDefaults.standard.set(focusPolicy.autoHide, forKey: Self.autoHideKey)
    }

    @objc private func openShortcutSettings() {
        _ = ShortcutStore.load(from: ShortcutStore.defaultURL)
        NSWorkspace.shared.open(ShortcutStore.defaultURL)
    }

    @objc private func reloadShortcutSettings() {
        compact?.setShortcuts(ShortcutStore.load(from: ShortcutStore.defaultURL))
    }

    private func addInfoItem(to menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        keyboard?.setEnabled(trusted)
        compact?.setEnabled(trusted)
        let symbol = trusted ? "keyboard" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TorqueController")
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
