import AppKit

let app = NSApplication.shared
// パネルもメニューバーのアイコンも出す前に判定する
if SingleInstance.isDuplicateOfRunningProcess() {
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
