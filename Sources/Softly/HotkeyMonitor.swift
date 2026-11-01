import AppKit
import CoreGraphics

/// Global key handling through a Quartz event tap.
///
/// Trigger: Right Option, alone (F9 is a media key on Mac keyboards).
/// Esc is swallowed only while the pill is showing, so apps get it otherwise.
/// Typing any key while Right Option is held (an Option shortcut or accented
/// character) is reported as a chord so a stray recording can be discarded.
@MainActor
final class HotkeyMonitor {
    static let triggerKeyCode: Int64 = 61     // kVK_RightOption
    static let escapeKeyCode: Int64 = 53      // kVK_Escape
    static let rightOptionMask: UInt64 = 0x40 // NX_DEVICERALTKEYMASK

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onChord: () -> Void = {}
    /// Return true to swallow Esc.
    var onEscape: () -> Bool = { false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var triggerDown = false

    var isRunning: Bool { tap != nil }

    /// Fails until Input Monitoring and Accessibility are granted.
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
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

    /// Returns true to swallow the event. Press/release/chord are deferred so
    /// starting the microphone never stalls system-wide typing in the tap.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.triggerKeyCode else { break }
            let down = event.flags.rawValue & Self.rightOptionMask != 0
            guard down != triggerDown else { break }
            triggerDown = down
            let action = down ? onPress : onRelease
            DispatchQueue.main.async { action() }
        case .keyDown:
            // Esc stays synchronous: it decides whether the key is swallowed.
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode, onEscape() {
                return true
            }
            if triggerDown {
                let chord = onChord
                DispatchQueue.main.async { chord() }
            }
        default:
            break
        }
        return false
    }
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
