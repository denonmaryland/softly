import AppKit
import CoreGraphics

/// Global key handling through a Quartz event tap.
///
/// Trigger: the chosen key alone, Right Option by default (F9 is a media key
/// on Mac keyboards, so a function key is opt-in). Esc is swallowed only
/// while the pill is showing, so apps get it otherwise. Typing any key while
/// the trigger is held (an Option shortcut or accented character) is
/// reported as a chord so a stray recording can be discarded.
@MainActor
final class HotkeyMonitor {
    static let escapeKeyCode: Int64 = 53      // kVK_Escape

    enum Capture { case key(Hotkey), unsupported, cancelled }

    var hotkey: Hotkey = .current {
        didSet { triggerDown = false }
    }
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onChord: () -> Void = {}
    /// Return true to swallow Esc.
    var onEscape: () -> Bool = { false }
    /// While set, the next key pressed is handed here instead of dictating.
    var onCapture: ((Capture) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var triggerDown = false

    var isRunning: Bool { tap != nil }

    /// Fails until Input Monitoring and Accessibility are granted.
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func finishCapture(_ result: Capture) {
        guard let capture = onCapture else { return }
        onCapture = nil
        DispatchQueue.main.async { capture(result) }
    }

    private func trigger(_ down: Bool) {
        guard down != triggerDown else { return }
        triggerDown = down
        let action = down ? onPress : onRelease
        DispatchQueue.main.async { action() }
    }

    /// Returns true to swallow the event. Press/release/chord are deferred so
    /// starting the microphone never stalls system-wide typing in the tap.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            if onCapture != nil {
                if let key = Hotkey.with(keyCode: code), let mask = key.deviceMask {
                    if event.flags.rawValue & mask != 0 { finishCapture(.key(key)) }
                } else if Self.otherModifiers.contains(code) {
                    finishCapture(.unsupported)
                }
                break
            }
            guard let mask = hotkey.deviceMask, code == hotkey.keyCode else { break }
            trigger(event.flags.rawValue & mask != 0)
        case .keyDown:
            if onCapture != nil {
                if code == Self.escapeKeyCode { finishCapture(.cancelled) }
                else if let key = Hotkey.with(keyCode: code), !key.isModifier { finishCapture(.key(key)) }
                else { finishCapture(.unsupported) }
                return true
            }
            // Esc stays synchronous: it decides whether the key is swallowed.
            if code == Self.escapeKeyCode, onEscape() {
                return true
            }
            if !hotkey.isModifier && code == hotkey.keyCode {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { trigger(true) }
                return true
            }
            if triggerDown {
                let chord = onChord
                DispatchQueue.main.async { chord() }
            }
        case .keyUp:
            if !hotkey.isModifier && code == hotkey.keyCode {
                trigger(false)
                return true
            }
        default:
            break
        }
        return false
    }

    /// Shift, Caps Lock, Fn and the left-hand modifiers: not usable alone.
    private static let otherModifiers: Set<Int64> = [55, 56, 57, 58, 59, 60, 63]
}

/// The tap is installed on the main run loop, so callbacks arrive on the main thread.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
