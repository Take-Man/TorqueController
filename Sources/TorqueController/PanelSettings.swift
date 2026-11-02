import AppKit

enum PanelID: String, CaseIterable {
    case compact, flick, qwerty
}

enum ScreenCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .topLeft: "左上"
        case .topRight: "右上"
        case .bottomLeft: "左下"
        case .bottomRight: "右下"
        }
    }

    /// macOS のホットコーナーの設定のキー。
    var hotCornerKey: String {
        switch self {
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }

    func point(in frame: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.maxX, y: frame.minY)
        }
    }

    /// point がこの隅の近くにあるか。
    func contains(_ point: CGPoint, in frame: CGRect, tolerance: CGFloat) -> Bool {
        let corner = self.point(in: frame)
        return abs(point.x - corner.x) <= tolerance && abs(point.y - corner.y) <= tolerance
    }
}

/// パネルの位置、倍率、不透明度と、四隅の設定の保存。
struct PanelSettings {
    static let scaleRange: ClosedRange<CGFloat> = 0.7...2
    static let scaleChoices: [CGFloat] = [0.7, 0.8, 0.9, 1, 1.1, 1.3, 1.5, 1.75, 2]
    static let opacityRange: ClosedRange<CGFloat> = 0.5...1
    static let opacityChoices: [CGFloat] = [1, 0.9, 0.75, 0.5]
    static let dwellChoices: [TimeInterval] = [0.5, 1, 1.5, 2]

    private enum Key {
        static let corners = "toggleCorners"
        static let dwell = "cornerDwell"
        static let hotCornerNotice = "hotCornerNoticeShown"
        static let keepsInScreen = "keepPanelsInScreen"
        static let mirrorsCandidates = "mirrorCandidates"
        static func origin(_ panel: PanelID) -> String { "panelOrigin.\(panel.rawValue)" }
        static func scale(_ panel: PanelID) -> String { "panelScale.\(panel.rawValue)" }
        static func opacity(_ panel: PanelID) -> String { "panelOpacity.\(panel.rawValue)" }
    }

    let defaults: UserDefaults

    func scale(of panel: PanelID) -> CGFloat {
        let stored = defaults.double(forKey: Key.scale(panel))
        guard stored > 0 else { return 1 }
        return min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, CGFloat(stored)))
    }

    func setScale(_ scale: CGFloat, of panel: PanelID) {
        defaults.set(Double(scale), forKey: Key.scale(panel))
    }

    func opacity(of panel: PanelID) -> CGFloat {
        let stored = defaults.double(forKey: Key.opacity(panel))
        guard stored > 0 else { return 1 }
        return min(Self.opacityRange.upperBound, max(Self.opacityRange.lowerBound, CGFloat(stored)))
    }

    func setOpacity(_ opacity: CGFloat, of panel: PanelID) {
        defaults.set(Double(opacity), forKey: Key.opacity(panel))
    }

    /// パネルとガイドが画面からはみ出さないように、動かせる範囲を制限する。
    var keepsInScreen: Bool {
        get { defaults.object(forKey: Key.keepsInScreen) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.keepsInScreen) }
    }

    /// 候補が隠れるときに左右反転する。
    var mirrorsCandidates: Bool {
        get { defaults.object(forKey: Key.mirrorsCandidates) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.mirrorsCandidates) }
    }

    var corners: Set<ScreenCorner> {
        get {
            guard let names = defaults.stringArray(forKey: Key.corners) else { return [.bottomRight] }
            return Set(names.compactMap(ScreenCorner.init(rawValue:)))
        }
        nonmutating set {
            defaults.set(newValue.map(\.rawValue), forKey: Key.corners)
        }
    }

    var dwell: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.dwell)
            return stored > 0 ? stored : 0.5
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.dwell)
        }
    }

    var hotCornerNoticeShown: Bool {
        get { defaults.bool(forKey: Key.hotCornerNotice) }
        nonmutating set { defaults.set(newValue, forKey: Key.hotCornerNotice) }
    }

    /// 動かしたことのないパネルは nil。
    func origin(of panel: PanelID) -> NSPoint? {
        guard let values = defaults.array(forKey: Key.origin(panel)) as? [Double], values.count == 2 else { return nil }
        return NSPoint(x: values[0], y: values[1])
    }

    func setOrigin(_ origin: NSPoint?, of panel: PanelID) {
        if let origin {
            defaults.set([Double(origin.x), Double(origin.y)], forKey: Key.origin(panel))
        } else {
            defaults.removeObject(forKey: Key.origin(panel))
        }
    }

    /// extent(パネルの左下を原点とした、パネルとガイドの全体の範囲)が bounds に収まるよう、位置を動かす。
    /// 収まらないほど大きいときは、左下をそろえる。
    static func clampedOrigin(_ origin: NSPoint, extent: CGRect, bounds: CGRect) -> NSPoint {
        func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            high < low ? low : min(high, max(low, value))
        }
        return NSPoint(
            x: clamp(origin.x, low: bounds.minX - extent.minX, high: bounds.maxX - extent.maxX),
            y: clamp(origin.y, low: bounds.minY - extent.minY, high: bounds.maxY - extent.maxY)
        )
    }

    /// 保存した位置が、今のどの画面にも掛からなければ(画面を外したときなど)使わない。
    static func isReachable(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.contains { $0.contains(center) }
    }
}

/// 隅に置いた時間の計測。切り替えたあとは、一度隅から離れるまで再び動かない。
struct CornerDwell: Equatable {
    var duration: TimeInterval
    private(set) var elapsed: TimeInterval = 0
    private var isArmed = true

    init(duration: TimeInterval) {
        self.duration = duration
    }

    /// 0 から 1 の進み具合。
    var progress: Double {
        isArmed ? min(1, elapsed / duration) : 0
    }

    /// 切り替える時が来たら true。
    mutating func update(isInCorner: Bool, delta: TimeInterval) -> Bool {
        guard isInCorner else {
            elapsed = 0
            isArmed = true
            return false
        }
        guard isArmed else { return false }
        elapsed += delta
        if elapsed >= duration {
            elapsed = 0
            isArmed = false
            return true
        }
        return false
    }
}

/// 待っている間の進み具合を示すリング。
final class CornerRingView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 3
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = Theme.Line.cornerRing
        Theme.Palette.cornerTrack.setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = Theme.Line.cornerRing
        arc.lineCapStyle = .round
        Theme.Palette.accent.setStroke()
        arc.stroke()
    }
}

/// 隅にカーソルを置くと、全パネルのオン/オフを切り替える。オフの間も監視は動かす。
@MainActor
final class CornerMonitor {
    private static let interval: TimeInterval = 0.05
    private static let tolerance: CGFloat = 6
    private static let ringSide: CGFloat = 44
    private static let ringInset: CGFloat = 10

    var corners: Set<ScreenCorner> = []
    var dwellDuration: TimeInterval {
        get { dwell.duration }
        set { dwell.duration = newValue }
    }
    var onTrigger: (() -> Void)?

    private var dwell = CornerDwell(duration: 0.5)
    private let ringPanel: FloatingPanel
    private let ringView = CornerRingView()
    private var timer: Timer?

    init() {
        ringPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.ringSide, height: Self.ringSide))
        ringPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
        ringPanel.ignoresMouseEvents = true
        ringPanel.hasShadow = false
        ringPanel.contentView = ringView
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) || abs($0.frame.maxX - location.x) < 2 || abs($0.frame.maxY - location.y) < 2 }
        let frame = screen?.frame
        let corner = frame.flatMap { frame in
            corners.first { $0.contains(location, in: frame, tolerance: Self.tolerance) }
        }

        // 修飾キーのドラッグなど、ボタンを押している間は反応しない
        let isInCorner = corner != nil && NSEvent.pressedMouseButtons == 0
        if dwell.update(isInCorner: isInCorner, delta: Self.interval) {
            onTrigger?()
        }

        if dwell.progress > 0, let corner, let frame {
            ringView.progress = dwell.progress
            ringPanel.setFrameOrigin(ringOrigin(corner: corner, frame: frame))
            ringPanel.orderFrontRegardless()
        } else {
            ringPanel.orderOut(nil)
        }
    }

    private func ringOrigin(corner: ScreenCorner, frame: CGRect) -> NSPoint {
        let point = corner.point(in: frame)
        let side = Self.ringSide + Self.ringInset
        return NSPoint(
            x: corner == .topLeft || corner == .bottomLeft ? point.x + Self.ringInset : point.x - side,
            y: corner == .bottomLeft || corner == .bottomRight ? point.y + Self.ringInset : point.y - side
        )
    }
}
