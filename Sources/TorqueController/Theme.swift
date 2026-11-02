import AppKit

/// 見た目の値の置き場所。方針と状態の表現の規則は DESIGN.md の「見た目」にある。
enum Theme {
    /// 色。システム色だけを使い、ライト/ダークに追従する。
    enum Palette {
        static var accent: NSColor { .controlAccentColor }
        /// 選択中の淡い塗り。
        static var accentTint: NSColor { accent.withAlphaComponent(0.12) }
        /// 中心の円にカーソルがあるときの塗り。
        static var accentHover: NSColor { accent.withAlphaComponent(0.25) }
        /// 候補の弧と直線。progress は開く動きの進み具合。
        static func accentDecoration(progress: CGFloat) -> NSColor { accent.withAlphaComponent(0.25 * progress) }

        /// ぼかしの上に重ねる色。背景が明るくても暗くても、文字とアクセント色が読めるよう明度をそろえる。
        static var panelVeil: NSColor { .windowBackgroundColor.withAlphaComponent(0.5) }
        /// キーの地。ダークの controlColor は明るく、アクセント色の文字が読みにくいので、より淡いシステム色を使う。
        static var key: NSColor { adaptive(light: .controlColor, dark: .quaternaryLabelColor) }
        static var dPadTrack: NSColor {
            adaptive(light: .controlColor.withAlphaComponent(0.25), dark: .quaternaryLabelColor.withAlphaComponent(0.05))
        }
        static var inputField: NSColor { .textBackgroundColor }
        /// ガイドと候補の下地。選ぶ瞬間に見えにくくしないよう不透明にする。
        static var guideBase: NSColor { .windowBackgroundColor }
        static var separator: NSColor { .separatorColor }
        /// 何も入力しない区画。色を付けない。
        static var neutralTint: NSColor { .quaternaryLabelColor }
        static var neutralStroke: NSColor { .secondaryLabelColor }
        static var cornerTrack: NSColor { guideBase.withAlphaComponent(0.8) }

        static var text: NSColor { .labelColor }
        static var secondaryText: NSColor { .secondaryLabelColor }
        static var tertiaryText: NSColor { .tertiaryLabelColor }

        private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }

        /// キーの文字に対する、上下左右の小さな文字の不透明度。
        static let hintAlpha: CGFloat = 0.7
        /// 今は使わないキーの不透明度。パネルの上に重ねるので、下げると明度が下がって見える。
        static let dimmedAlpha: CGFloat = 0.3
    }

    /// パネルと入力欄の背景の素材。
    static let panelMaterial = NSVisualEffectView.Material.hudWindow

    /// 線の太さ。
    enum Line {
        static let thin: CGFloat = 1
        static let emphasis: CGFloat = 1.5
        /// 四隅の進み具合のリング。
        static let cornerRing: CGFloat = 4
    }

    /// 角丸の半径。
    enum Radius {
        static let panel: CGFloat = 12
        static let key: CGFloat = 8
        static let candidate: CGFloat = 6
        static let dPadBlock: CGFloat = 4
    }

    /// 余白。
    enum Space {
        static let panelPadding: CGFloat = 8
        static let keyGap: CGFloat = 6
        static let qwertyKeyGap: CGFloat = 4
        /// 初期配置での、パネルの間。
        static let panelGap: CGFloat = 6
        /// QWERTY の下に、入力欄を置く分だけ空ける。
        static let qwertyLift: CGFloat = 56
        /// キーの文字を小さくするときに、左右に残す幅。
        static let keyLabelInset: CGFloat = 4
        static let keyHintInset: CGFloat = 4
        static let dPadBlockInset: CGFloat = 1
        static let inputFieldText: CGFloat = 8
        /// 入力欄の開閉のマークを置く、上端の帯の高さ。
        static let inputFieldToggle: CGFloat = 18
        /// スコープの文字列と中心の円の間。
        static let scope: CGFloat = 6
        static let candidateText: CGFloat = 3
        static let candidateCell: CGFloat = 14
        /// 固定中の、外側の輪と内側の輪の間。
        static let lockedRing: CGFloat = 3
        /// 押したときの輪が、キーの外へ広がる幅。
        static let pressRing: CGFloat = 3
        /// ガイドの直線の先端と文字の中心の間。
        static let spokeToLabel: CGFloat = 12
        static let gripDotSpacing: CGFloat = 7
    }

    /// 文字と記号の大きさ。
    enum FontSize {
        static let keyLabel: CGFloat = 22
        static let keyLongLabel: CGFloat = 15
        static let keyHint: CGFloat = 10
        static let keySymbol: CGFloat = 18
        static let dPadArrow: CGFloat = 11
        static let inputField: CGFloat = 18
        static let inputFieldToggle: CGFloat = 11
        static let flickGuide: CGFloat = 18
        static let shortcutRadial: CGFloat = 15
        static let candidate: CGFloat = 15
        static let candidateSymbol: CGFloat = 13
    }

    /// 動きの時間(秒)。
    enum Motion {
        static let modeSlide: TimeInterval = 0.18
        static let inputFieldToggle: TimeInterval = 0.2
        static let candidateReveal: CFTimeInterval = 0.26
        static let candidateColumnDelay: CFTimeInterval = 0.025
        static let guideReveal: CFTimeInterval = 0.12
        static let pressRing: CFTimeInterval = 0.2
        static let rippleExpand: CFTimeInterval = 0.6
        static let rippleFade: CFTimeInterval = 0.15
    }

    /// パネルの背景の波紋。半径には bounds の倍率が掛かる。
    enum Ripple {
        /// 内側から順に。外側ほど薄い。
        static let rings: [(radius: CGFloat, opacity: Float)] = [(60, 0.35), (100, 0.25), (140, 0.15)]
        /// 終わりに漸近的に近づく、強いイーズアウト。
        static var expandTiming: CAMediaTimingFunction {
            CAMediaTimingFunction(controlPoints: 0.1, 0.9, 0.2, 1)
        }
    }

    /// 選択中の表現。淡い塗りと、強調の太さの輪郭線。
    static func drawActive(_ path: NSBezierPath) {
        Palette.accentTint.setFill()
        path.fill()
        drawRing(path)
    }

    static func drawRing(_ path: NSBezierPath) {
        Palette.accent.setStroke()
        path.lineWidth = Line.emphasis
        path.stroke()
    }

    /// 輪郭線がビューの外で切れないよう、線の太さの半分だけ内側に寄せた角丸の四角。
    static func ringPath(in rect: NSRect, cornerRadius: CGFloat, inset: CGFloat = Line.emphasis / 2) -> NSBezierPath {
        let radius = max(0, cornerRadius - inset)
        return NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
    }
}
