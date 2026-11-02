import AppKit
import Carbon

/// フォーカスしている要素の種類。
enum FocusKind: Equatable {
    case none, text, secure

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// 選択範囲を設定できれば文字入力欄とみなすロール(HTML の編集可能な領域など)。
    /// Chrome はチェックボックスでも設定可能と答えるので、ロールを絞る。
    private static let editableContainerRoles: Set<String> = ["AXGroup", "AXWebArea"]

    /// セキュア入力が有効なら、要素が取れなくてもパスワード欄として扱う(ブラウザでは要素を取れないことがある)。
    static func classify(role: String?, subrole: String?, hasSettableSelection: Bool, isSecureInput: Bool) -> FocusKind {
        if isSecureInput || subrole == "AXSecureTextField" {
            return .secure
        }
        guard let role else { return .none }
        if textRoles.contains(role) {
            return .text
        }
        return hasSettableSelection && editableContainerRoles.contains(role) ? .text : .none
    }
}

/// フォーカスの変化からフリックパネルの表示を決める。手動の切替は、次にフォーカスが変わるまで保たれる。
struct FocusPolicy: Equatable {
    /// フォーカスが外れたと判断するまでの、連続した観測の回数。アプリの切替で一瞬外れただけのときに隠さない。
    private static let requiredNoneObservations = 2

    /// 文字入力欄にフォーカスしたら出す。
    var autoShow = true
    /// フォーカスが外れたら隠す。
    var autoHide = false

    private(set) var kind = FocusKind.none
    private(set) var flickVisible = false
    private var noneObservations = 0

    /// 定期的な観測を反映する。表示に関わる変化があれば true。
    mutating func observe(kind newKind: FocusKind, elementChanged: Bool) -> Bool {
        if newKind == .none, kind != .none {
            noneObservations += 1
            if noneObservations < Self.requiredNoneObservations {
                return false
            }
        }
        noneObservations = 0
        guard elementChanged || newKind != kind else { return false }
        kind = newKind
        switch newKind {
        case .text:
            if autoShow {
                flickVisible = true
            }
        case .none:
            if autoHide {
                flickVisible = false
            }
        case .secure:
            // 平文が出ないよう、設定によらず隠す。手動では出せる
            flickVisible = false
        }
        return true
    }

    mutating func userToggledFlick() {
        flickVisible.toggle()
    }
}

/// アクセシビリティ API で、フォーカスしている要素を定期的に調べる。
@MainActor
final class FocusMonitor {
    private static let interval: TimeInterval = 0.3
    /// 応答しないアプリがあっても、キーボードを止めない。
    private static let messagingTimeout: Float = 0.05

    /// 観測のたびに、種類と要素が変わったかを伝える。
    var onObserve: ((FocusKind, Bool) -> Void)?

    private let systemWide = AXUIElementCreateSystemWide()
    private var lastElement: AXUIElement?
    private var timer: Timer?

    func start() {
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        // 権限がないときは判定できないので、表示を変えない
        guard result != .apiDisabled else { return }
        // AXUIElement は CFTypeRef から必ず変換できる
        let element = result == .success ? (value as! AXUIElement?) : nil

        let role = element.flatMap { attribute(kAXRoleAttribute, of: $0) }
        let subrole = element.flatMap { attribute(kAXSubroleAttribute, of: $0) }
        var isSettable = DarwinBoolean(false)
        if let element {
            AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &isSettable)
        }
        let isSecureInput = IsSecureEventInputEnabled()
        let kind = FocusKind.classify(role: role, subrole: subrole, hasSettableSelection: isSettable.boolValue, isSecureInput: isSecureInput)
        let changed: Bool
        switch (element, lastElement) {
        case (nil, nil): changed = false
        case let (current?, last?): changed = !CFEqual(current, last)
        default: changed = true
        }
        lastElement = element
        onObserve?(kind, changed)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
