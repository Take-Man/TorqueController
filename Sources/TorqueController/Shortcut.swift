import CoreGraphics
import Foundation

enum Modifier: CaseIterable, Hashable {
    case command, shift, option, control

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .shift: .maskShift
        case .option: .maskAlternate
        case .control: .maskControl
        }
    }

    /// 常に左側のキーコード。AirController は右 command の単独押しを使うので、衝突させない。
    var leftKeyCode: CGKeyCode {
        switch self {
        case .command: 55
        case .shift: 56
        case .option: 58
        case .control: 59
        }
    }

    init?(name: String) {
        switch name {
        case "command", "cmd": self = .command
        case "shift": self = .shift
        case "option", "alt": self = .option
        case "control", "ctrl": self = .control
        default: return nil
        }
    }
}

/// 設定済みのショートカット。修飾キーの組み合わせは順序なしで等価に扱う。key は小文字の1文字。
struct Shortcut: Hashable {
    let modifiers: Set<Modifier>
    let key: String

    /// 「command+shift+4」の形から作る。
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, key.count == 1, parts.count >= 2 else { return nil }
        let modifiers = parts.dropLast().map(Modifier.init(name:))
        guard !modifiers.contains(nil) else { return nil }
        self.modifiers = Set(modifiers.compactMap { $0 })
        self.key = key
    }

    static let defaults = [
        "command+x", "command+c", "command+v", "command+s", "command+q", "command+z",
        "command+shift+3", "command+shift+4", "command+shift+z", "control+c",
    ]
}

/// ショートカットの設定ファイル。利用者が編集し、メニューから読み直す。
enum ShortcutStore {
    private struct File: Codable {
        var shortcuts: [String]
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TorqueController/shortcuts.json")
    }

    /// ファイルがなければ初期設定で作る。読めない行は飛ばす。ファイルが壊れていれば初期設定を使い、上書きはしない。
    static func load(from url: URL) -> [Shortcut] {
        if !FileManager.default.fileExists(atPath: url.path) {
            writeDefaults(to: url)
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            return parse(file.shortcuts)
        } catch {
            NSLog("ショートカットの設定を読めません: %@", String(describing: error))
            return parse(Shortcut.defaults)
        }
    }

    static func parse(_ texts: [String]) -> [Shortcut] {
        texts.compactMap { text in
            let shortcut = Shortcut(text)
            if shortcut == nil {
                NSLog("ショートカットの書き方が違います: %@", text)
            }
            return shortcut
        }
    }

    private static func writeDefaults(to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(File(shortcuts: Shortcut.defaults)).write(to: url, options: .atomic)
        } catch {
            NSLog("ショートカットの設定を作れません: %@", String(describing: error))
        }
    }
}

/// 修飾キーからのドラッグで出す、階層型の同心円の配置。左側90度はキャンセルで、残り270度を、
/// その先にあるショートカットの数に比例して割り当てる。位置は 0(左上の境界)から時計回りに 270(左下の境界)で表す。
struct ShortcutRadial {
    static let centerRadius: CGFloat = 26
    static let ringWidth: CGFloat = 54
    static let span: CGFloat = 270

    struct Node: Equatable {
        enum Kind: Equatable {
            case key(Shortcut)
            case modifier(Modifier)
        }

        let kind: Kind
        let start: CGFloat
        let end: CGFloat
        let ring: Int
        let children: [Node]

        var label: String {
            switch kind {
            case .key(let shortcut): shortcut.key.uppercased()
            case .modifier(let modifier): modifier.symbol
            }
        }
    }

    enum Selection: Equatable {
        case center
        case cancel
        /// 外側へたどった項目の列。
        case path([Node])
    }

    let origin: Modifier
    let roots: [Node]

    init(origin: Modifier, shortcuts: [Shortcut]) {
        self.origin = origin
        roots = Self.nodes(held: [origin], shortcuts: shortcuts, start: 0, span: Self.span, ring: 0)
    }

    private static func nodes(held: Set<Modifier>, shortcuts: [Shortcut], start: CGFloat, span: CGFloat, ring: Int) -> [Node] {
        var entries: [(kind: Node.Kind, weight: Int, held: Set<Modifier>)] = []
        for shortcut in shortcuts where shortcut.modifiers == held {
            entries.append((.key(shortcut), 1, held))
        }
        for modifier in Modifier.allCases where !held.contains(modifier) {
            let next = held.union([modifier])
            let count = shortcuts.filter { next.isSubset(of: $0.modifiers) }.count
            if count > 0 {
                entries.append((.modifier(modifier), count, next))
            }
        }

        let total = entries.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        var position = start
        return entries.map { entry in
            let width = span * CGFloat(entry.weight) / CGFloat(total)
            defer { position += width }
            var children: [Node] = []
            if case .modifier = entry.kind {
                children = nodes(held: entry.held, shortcuts: shortcuts, start: position, span: width, ring: ring + 1)
            }
            return Node(kind: entry.kind, start: position, end: position + width, ring: ring, children: children)
        }
    }

    /// 押した位置からの移動量で選ぶ。y は上が正。
    func selection(offset: CGVector) -> Selection {
        let distance = hypot(offset.dx, offset.dy)
        if distance < Self.centerRadius { return .center }
        let angle = atan2(offset.dy, offset.dx) * 180 / .pi
        guard abs(angle) < 135 else { return .cancel }
        let position = 135 - angle
        let reach = Int((distance - Self.centerRadius) / Self.ringWidth)

        var path: [Node] = []
        var nodes = roots
        while let node = nodes.first(where: { position >= $0.start && position < $0.end }) {
            path.append(node)
            guard node.ring < reach else { break }
            nodes = node.children
        }
        return .path(path)
    }

    /// 今の選択で表示する項目。1列目の全てと、選んでいる修飾キーの先の列。
    func visibleNodes(for selection: Selection) -> [Node] {
        var result = roots
        if case .path(let path) = selection {
            for node in path {
                result += node.children
            }
        }
        return result
    }

    /// 外側まで開いたときの半径。
    static func maxRadius(depth: Int) -> CGFloat {
        centerRadius + ringWidth * CGFloat(depth)
    }

    var depth: Int {
        func depth(of nodes: [Node]) -> Int {
            nodes.map { 1 + depth(of: $0.children) }.max() ?? 0
        }
        return depth(of: roots)
    }
}

extension Set where Element == Modifier {
    var flags: CGEventFlags {
        reduce(into: CGEventFlags()) { $0.insert($1.flag) }
    }
}
