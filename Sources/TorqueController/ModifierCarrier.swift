import CoreGraphics
import Foundation
import Synchronization

/// コンパクトパネルで選んだ修飾キーを、カーソル操作(クリック、ドラッグ、スクロール)に乗せるかの判定。
/// 時刻と位置を受け取るだけの状態で、イベントタップと UI から独立させてテストする。
/// 固定していない選択は、操作が終わったら(下の解除の時機)外す。固定した選択は外さない。
struct ModifierCarrier {
    /// 段階の情報がないマウスホイールは、最後のスクロールからこれだけ空いたら解除する。
    /// トラックパッドで指を離したあと、慣性のスクロールが始まるのを待つ時間にも使う。
    static let scrollIdle: TimeInterval = 0.3
    /// 離したあと、この距離以内でもう一度押されたら、同じ操作の続き(ダブルクリックなど)とみなす。
    static let repressDistance: CGFloat = 6

    /// スクロールのイベントの種類。CGEvent の段階の値から作る。
    enum Scroll: Equatable {
        /// 段階の情報がない(マウスホイール)。
        case wheel
        /// 指がトラックパッドに触れて動かしている。
        case touching
        /// 指を離した、または取り消した。このあと慣性が続くことがある。
        case lifted
        /// 慣性のスクロールの途中。
        case momentum
        /// 慣性のスクロールが終わった。
        case momentumEnded

        /// scrollPhase と momentumPhase(CGEvent のフィールドの値)から作る。
        init(scrollPhase: Int64, momentumPhase: Int64) {
            switch momentumPhase {
            case 3: self = .momentumEnded
            case 1, 2: self = .momentum
            default:
                switch scrollPhase {
                case 0: self = .wheel
                case 4, 8: self = .lifted
                default: self = .touching
                }
            }
        }
    }

    /// 1つのイベントに対する結果。flags をイベントのフラグに足す。released は、このイベントで固定していない選択を外したか。
    struct Outcome: Equatable {
        var flags: CGEventFlags
        var released: Bool
    }

    private enum Pending: Equatable {
        case none
        /// クリックやドラッグを離した。期限までに近くで押されれば、それにも乗せる。
        case repress(CGPoint, deadline: TimeInterval)
        /// スクロールの途中。期限がなければ、指が触れている間なので待ち続ける。
        case scroll(deadline: TimeInterval?)
    }

    var doubleClickInterval: TimeInterval
    /// 選んでいる修飾キー全体(固定を含む)。
    private(set) var selected: CGEventFlags = []
    /// そのうち固定したもの。
    private(set) var locked: CGEventFlags = []
    /// 押しているボタンと、押したときに乗せたフラグ。自分のパネルなど対象外の押下は空のフラグで持つ。
    private var held: [Int64: CGEventFlags] = [:]
    private var pending = Pending.none

    init(doubleClickInterval: TimeInterval) {
        self.doubleClickInterval = doubleClickInterval
    }

    /// 1回で外れる選択。
    var transient: CGEventFlags { selected.subtracting(locked) }

    var isActive: Bool { !selected.isEmpty }

    /// 解除する時刻。なければ、今は時間で解除しない。
    var deadline: TimeInterval? {
        switch pending {
        case .none: nil
        case .repress(_, let deadline): deadline
        case .scroll(let deadline): deadline
        }
    }

    /// パネルの選択が変わったとき。待っていた解除は捨てる(選択はパネルの側で決まっている)。押しているボタンは覚えたまま。
    mutating func configure(selected: CGEventFlags, locked: CGEventFlags) {
        self.selected = selected
        self.locked = locked.intersection(selected)
        pending = .none
    }

    /// ボタンを押した。isOwn は TorqueController 自身が受け取る操作。
    mutating func press(button: Int64, at location: CGPoint, time: TimeInterval, isOwn: Bool) -> Outcome {
        var released = expire(at: time)
        if isOwn {
            held[button] = []
            return Outcome(flags: [], released: released)
        }
        switch pending {
        case .repress(let point, _):
            if hypot(location.x - point.x, location.y - point.y) > Self.repressDistance {
                released = release() || released
            }
        case .scroll:
            // スクロールのあとのクリックは別の操作。スクロールで選択を使い終えたとする
            released = release() || released
        case .none:
            break
        }
        pending = .none
        held[button] = selected
        return Outcome(flags: selected, released: released)
    }

    /// 押したままの移動。押したときと同じフラグを乗せる。
    func drag(button: Int64) -> CGEventFlags {
        held[button] ?? []
    }

    /// ボタンを離した。押したときと同じフラグを乗せ、全てのボタンが離れたら、もう一度の押下を待つ。
    mutating func release(button: Int64, at location: CGPoint, time: TimeInterval) -> Outcome {
        guard let flags = held.removeValue(forKey: button) else {
            return Outcome(flags: [], released: expire(at: time))
        }
        if held.values.allSatisfy(\.isEmpty), !flags.intersection(transient).isEmpty {
            pending = .repress(location, deadline: time + doubleClickInterval)
        }
        return Outcome(flags: flags, released: false)
    }

    mutating func scroll(_ kind: Scroll, time: TimeInterval, isOwn: Bool) -> Outcome {
        var released = expire(at: time)
        if isOwn {
            return Outcome(flags: [], released: released)
        }
        // ドラッグしながらのスクロールは、ドラッグの一部として扱う
        if held.values.contains(where: { !$0.isEmpty }) {
            return Outcome(flags: selected, released: released)
        }
        if case .repress = pending {
            released = release() || released
        }
        let flags = selected
        if !transient.isEmpty {
            switch kind {
            case .wheel, .lifted, .momentum:
                pending = .scroll(deadline: time + Self.scrollIdle)
            case .touching:
                pending = .scroll(deadline: nil)
            case .momentumEnded:
                released = release() || released
            }
        }
        return Outcome(flags: flags, released: released)
    }

    /// 期限が過ぎていれば、固定していない選択を外す。外したら真。
    mutating func expire(at time: TimeInterval) -> Bool {
        guard let deadline, time >= deadline else { return false }
        return release()
    }

    private mutating func release() -> Bool {
        pending = .none
        guard !transient.isEmpty else { return false }
        selected = locked
        return true
    }
}

/// ModifierCarrier の判定でマウスのイベントのフラグを書き換える CGEventTap。修飾キーのキーイベントは送らない。
/// 選んだ修飾キーがあるときだけ有効にし、それ以外はタップを無効にしてマウスの操作に触れない。
/// タップは専用のスレッドの実行ループで動かし、メインスレッドの処理を待たない。
final class ModifierTap: @unchecked Sendable {
    private struct State {
        var carrier: ModifierCarrier
        /// パネルが選択を更新するたびに増やす。古い選択への解除の知らせを捨てるため。
        var generation = 0
    }

    private static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
    ].reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }

    private let state: Mutex<State>
    private let ownPID = Int64(getpid())
    private let timerQueue = DispatchQueue(label: "TorqueController.ModifierTap.timer")
    private let timer: DispatchSourceTimer
    private let tapLock = NSLock()
    private var tap: CFMachPort?
    private var thread: Thread?

    /// 固定していない選択を外したとき。メインスレッドで、外したときの世代を渡す。
    var onRelease: (@MainActor (Int) -> Void)?

    init(doubleClickInterval: TimeInterval) {
        state = Mutex(State(carrier: ModifierCarrier(doubleClickInterval: doubleClickInterval)))
        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.setEventHandler { [weak self] in self?.timerFired() }
        timer.schedule(deadline: .distantFuture)
        timer.resume()
    }

    var generation: Int { state.withLock { $0.generation } }

    /// パネルの選択を渡す。空ならタップを無効にする。権限がなくタップを作れなければ、次の呼び出しでまた試す。
    func update(selected: CGEventFlags, locked: CGEventFlags, doubleClickInterval: TimeInterval) {
        state.withLock {
            $0.generation += 1
            $0.carrier.doubleClickInterval = doubleClickInterval
            $0.carrier.configure(selected: selected, locked: locked)
        }
        reschedule()
        let isActive = !selected.isEmpty
        if isActive {
            startIfNeeded()
        }
        tapLock.withLock {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: isActive)
            }
        }
    }

    // MARK: - タップのスレッド

    private func startIfNeeded() {
        guard thread == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            let tap = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.mask,
                callback: { _, type, event, info in
                    guard let info else { return Unmanaged.passUnretained(event) }
                    let tap = Unmanaged<ModifierTap>.fromOpaque(info).takeUnretainedValue()
                    return tap.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            self.tapLock.withLock { self.tap = tap }
            ready.signal()
            guard let tap else { return }
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "TorqueController.ModifierTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if tapLock.withLock({ tap }) == nil {
            NSLog("修飾キーをクリックに乗せるイベントタップを作れません(アクセシビリティの許可を確認してください)")
            return
        }
        self.thread = thread
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // システムに無効にされた。選択中なら有効に戻す
            if state.withLock({ $0.carrier.isActive }) {
                tapLock.withLock {
                    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let isOwn = event.getIntegerValueField(.eventTargetUnixProcessID) == ownPID
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let location = event.location
            apply(to: event) { $0.press(button: button, at: location, time: now, isOwn: isOwn) }
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let flags = state.withLock { $0.carrier.drag(button: button) }
            if !flags.isEmpty {
                event.flags.formUnion(flags)
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let location = event.location
            apply(to: event) { $0.release(button: button, at: location, time: now) }
        case .scrollWheel:
            let isOwn = event.getIntegerValueField(.eventTargetUnixProcessID) == ownPID
            let kind = ModifierCarrier.Scroll(
                scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            )
            apply(to: event) { $0.scroll(kind, time: now, isOwn: isOwn) }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func apply(to event: CGEvent, _ body: (inout ModifierCarrier) -> ModifierCarrier.Outcome) {
        let (outcome, generation, deadline) = state.withLock { state in
            let outcome = body(&state.carrier)
            return (outcome, state.generation, state.carrier.deadline)
        }
        if !outcome.flags.isEmpty {
            event.flags.formUnion(outcome.flags)
        }
        schedule(deadline)
        if outcome.released {
            notifyRelease(generation)
        }
    }

    // MARK: - 時間での解除

    private func reschedule() {
        schedule(state.withLock { $0.carrier.deadline })
    }

    private func schedule(_ deadline: TimeInterval?) {
        guard let deadline else {
            timer.schedule(deadline: .distantFuture)
            return
        }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        timer.schedule(deadline: .now() + delay)
    }

    private func timerFired() {
        let now = ProcessInfo.processInfo.systemUptime
        let (released, generation, deadline) = state.withLock { state in
            (state.carrier.expire(at: now), state.generation, state.carrier.deadline)
        }
        schedule(deadline)
        if released {
            notifyRelease(generation)
        }
    }

    private func notifyRelease(_ generation: Int) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onRelease?(generation)
            }
        }
    }
}
