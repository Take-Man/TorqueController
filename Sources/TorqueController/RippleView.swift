import AppKit

/// 押すと波紋を出すキー。無効なキーでは出さない。
@MainActor
protocol RippleSource {
    var firesRipple: Bool { get }
}

/// パネルの背景の波紋。ぼかしの上、キーの後ろに置き、パネルの形で切り抜く。
/// レイヤーは3本だけ作って使い回す。動きは Core Animation に任せ、広がり切った後は何も動かさない。
final class RippleView: NSView {
    private let clipLayer = CALayer()
    private let rings: [CAShapeLayer]
    /// 表示中の波紋の起点。消えている間と消している途中は nil。
    private(set) var origin: NSPoint?
    /// 今の波紋が消えた後に広げる起点。消している途中に押されたら、最後の位置だけを覚える。
    private(set) var pendingOrigin: NSPoint?
    private var fadeTimer: Timer?

    /// 「視差効果を減らす」。テストで差し替える。
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isEnabled = true {
        didSet {
            if !isEnabled { clear() }
        }
    }
    /// 線の太さは倍率によらず同じにする。半径は bounds の倍率がそのまま掛かる。
    var scale: CGFloat = 1 {
        didSet { updateLineWidth() }
    }

    var ringCount: Int { rings.count }
    var isFading: Bool { fadeTimer != nil }

    override init(frame frameRect: NSRect) {
        rings = Theme.Ripple.rings.map { ring in
            let layer = CAShapeLayer()
            // 原点を中心に描き、position を起点に合わせる。bounds が空なので、拡大の中心も起点になる
            layer.path = CGPath(
                ellipseIn: CGRect(x: -ring.radius, y: -ring.radius, width: ring.radius * 2, height: ring.radius * 2),
                transform: nil
            )
            layer.fillColor = nil
            layer.opacity = 0
            return layer
        }
        super.init(frame: frameRect)
        wantsLayer = true
        clipLayer.cornerRadius = Theme.Radius.panel
        clipLayer.masksToBounds = true
        clipLayer.frame = bounds
        layer?.addSublayer(clipLayer)
        rings.forEach(clipLayer.addSublayer)
        updateLineWidth()
        updateColor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsChanged),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        withoutImplicitAnimation { clipLayer.frame = bounds }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    @objc private func systemColorsChanged() {
        updateColor()
    }

    /// 押された位置から波紋を出す。前の波紋があれば、消してから広げる。
    func ripple(at point: NSPoint) {
        guard isEnabled else { return }
        if reducesMotion() {
            fadeTimer?.invalidate()
            fadeTimer = nil
            pendingOrigin = nil
            start(at: point, animated: false)
        } else if origin == nil, !isFading {
            start(at: point, animated: true)
        } else {
            pendingOrigin = point
            if !isFading {
                fadeOut()
            }
        }
    }

    private func start(at point: NSPoint, animated: Bool) {
        origin = point
        withoutImplicitAnimation {
            for (layer, ring) in zip(rings, Theme.Ripple.rings) {
                layer.removeAllAnimations()
                layer.position = point
                layer.transform = CATransform3DIdentity
                layer.opacity = ring.opacity
                if animated {
                    let expand = CABasicAnimation(keyPath: "transform.scale")
                    expand.fromValue = 0
                    expand.toValue = 1
                    expand.duration = Theme.Motion.rippleExpand
                    expand.timingFunction = Theme.Ripple.expandTiming
                    layer.add(expand, forKey: nil)
                }
            }
        }
    }

    /// 今の位置と大きさのまま消す。
    private func fadeOut() {
        origin = nil
        withoutImplicitAnimation {
            for layer in rings {
                let current = layer.presentation()
                let opacity = current?.opacity ?? layer.opacity
                layer.transform = current?.transform ?? layer.transform
                layer.removeAllAnimations()
                layer.opacity = 0
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = opacity
                fade.toValue = 0
                fade.duration = Theme.Motion.rippleFade
                layer.add(fade, forKey: nil)
            }
        }
        // 隠れたパネルでは Core Animation の完了が当てにならないので、時間で次へ進める
        let timer = Timer(timeInterval: Theme.Motion.rippleFade, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeFinished() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func fadeFinished() {
        fadeTimer = nil
        if let pendingOrigin {
            self.pendingOrigin = nil
            start(at: pendingOrigin, animated: true)
        }
    }

    private func clear() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        origin = nil
        pendingOrigin = nil
        withoutImplicitAnimation {
            for layer in rings {
                layer.removeAllAnimations()
                layer.opacity = 0
            }
        }
    }

    private func updateLineWidth() {
        withoutImplicitAnimation {
            for layer in rings {
                layer.lineWidth = Theme.Line.thin / scale
            }
        }
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = Theme.Palette.accent.cgColor
            withoutImplicitAnimation {
                for layer in rings {
                    layer.strokeColor = color
                }
            }
        }
    }

    private func withoutImplicitAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
