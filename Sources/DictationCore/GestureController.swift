// Key gesture state machine, ported from the Linux plugin's Controller.js.
// The adapter owns timers and recording; this only decides what to do.
//
//  Hold the key            → record while held, transcribe on release.
//  Double-tap              → latch hands-free; press again to finish.
//  Quick single tap        → waits `doubleTapWindow` for a second press, then stops.

public enum RecorderState: Equatable, Sendable {
    case idle, recording, transcribing
}

public enum GestureEvent: Equatable, Sendable {
    case press, release, toggle, timeout, reset, stop, cancel
}

public enum GestureAction: Equatable, Sendable {
    case start, stop, cancel, timerStart, timerStop
}

public struct GestureController: Sendable {
    /// Releases faster than this count as a tap.
    public static let tapLimit: Double = 0.240
    /// A second press within this window after a tap latches hands-free mode.
    public static let doubleTapWindow: Double = 0.330

    public private(set) var held = false
    public private(set) var locked = false
    public private(set) var owned = false
    public private(set) var waiting = false
    private var ignoreRelease = false
    private var pressedAt: Double = 0
    private var releasedAt: Double = 0

    public init() {}

    /// - Parameters:
    ///   - now: monotonic seconds.
    ///   - state: the recorder state as currently known to the adapter.
    public mutating func send(_ event: GestureEvent, now: Double, state: RecorderState) -> [GestureAction] {
        var out: [GestureAction] = []
        switch event {
        case .reset:
            locked = false; owned = false; waiting = false
            ignoreRelease = held
            out.append(.timerStop)
        case .stop, .cancel:
            locked = false; owned = false; waiting = false
            ignoreRelease = held
            out.append(.timerStop)
            out.append(event == .stop ? .stop : .cancel)
        case .toggle:
            if owned || state == .recording {
                return send(.stop, now: now, state: state)
            }
            guard state == .idle else { return out }
            owned = true; locked = true
            out.append(.start)
        case .press:
            guard !held else { return out }
            held = true
            pressedAt = now
            if waiting && now - releasedAt <= Self.doubleTapWindow {
                waiting = false
                locked = true
                out.append(.timerStop)
            } else if locked || (!owned && state == .recording) {
                ignoreRelease = true
                out = send(.stop, now: now, state: state)
            } else if state == .idle && !owned {
                owned = true
                out.append(.start)
            } else {
                ignoreRelease = true
            }
        case .release:
            guard held else { return out }
            held = false
            if ignoreRelease { ignoreRelease = false; return out }
            if locked || !owned { return out }
            if now - pressedAt <= Self.tapLimit {
                waiting = true
                releasedAt = now
                out.append(.timerStart)
            } else {
                owned = false
                out.append(.stop)
            }
        case .timeout:
            if waiting {
                waiting = false; owned = false
                out.append(.stop)
            }
        }
        return out
    }
}
