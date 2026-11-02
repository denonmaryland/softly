// Key gesture state machine, ported from the Linux plugin's Controller.js.
// The adapter owns recording; this only decides what to do.
//
//  Tap the key             → start hands-free; tap again to finish.
//  Hold the key            → record while held, transcribe on release.
//  With tapToStart off, every press is push-to-talk: release always finishes.

public enum RecorderState: Equatable, Sendable {
    case idle, recording, transcribing
}

public enum GestureEvent: Equatable, Sendable {
    case press, release, toggle, reset, stop, cancel
}

public enum GestureAction: Equatable, Sendable {
    case start, stop, cancel
}

public struct GestureController: Sendable {
    /// Presses shorter than this are taps and keep recording hands-free;
    /// longer ones are push-to-talk and finish on release.
    public static let holdThreshold: Double = 0.5

    /// The "Tap to start and stop" setting. Off means hold-only.
    public var tapToStart = true

    public private(set) var held = false
    public private(set) var locked = false
    public private(set) var owned = false
    private var ignoreRelease = false
    private var pressedAt: Double = 0

    public init() {}

    /// - Parameters:
    ///   - now: monotonic seconds.
    ///   - state: the recorder state as currently known to the adapter.
    public mutating func send(_ event: GestureEvent, now: Double, state: RecorderState) -> [GestureAction] {
        switch event {
        case .reset:
            locked = false; owned = false
            ignoreRelease = held
            return []
        case .stop, .cancel:
            locked = false; owned = false
            ignoreRelease = held
            return [event == .stop ? .stop : .cancel]
        case .toggle:
            if owned || state == .recording { return send(.stop, now: now, state: state) }
            guard state == .idle else { return [] }
            owned = true; locked = true
            return [.start]
        case .press:
            guard !held else { return [] }
            held = true
            pressedAt = now
            if locked || (!owned && state == .recording) {
                ignoreRelease = true
                return send(.stop, now: now, state: state)
            }
            if state == .idle && !owned {
                owned = true
                return [.start]
            }
            ignoreRelease = true
            return []
        case .release:
            guard held else { return [] }
            held = false
            if ignoreRelease { ignoreRelease = false; return [] }
            if locked || !owned { return [] }
            if tapToStart && now - pressedAt < Self.holdThreshold {
                locked = true
                return []
            }
            owned = false
            return [.stop]
        }
    }
}
