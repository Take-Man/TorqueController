import AppKit
import Carbon
import TorqueEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var keyboard: FlickKeyboard?
    private var permissionTimer: Timer?
    private var isDictionaryLoaded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        keyboard = FlickKeyboard(converter: loadConverter(), learningURL: LearningModel.defaultURL)
        keyboard?.show()

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
        addInfoItem(to: menu, "セキュア入力: \(IsSecureEventInputEnabled() ? "有効" : "無効")")
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

    private func addInfoItem(to menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        keyboard?.setEnabled(trusted)
        let symbol = trusted ? "keyboard" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TorqueController")
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
