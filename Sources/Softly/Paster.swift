import AppKit
import CoreGraphics

/// Puts the transcript on the clipboard and sends ⌘V to the frontmost app.
/// Like the Linux helper, the transcript stays on the clipboard afterwards,
/// so it can be pasted again if the field didn't accept it.
@MainActor
enum Paster {
    nonisolated private static let vKey: CGKeyCode = 9 // kVK_ANSI_V
    nonisolated private static let returnKey: CGKeyCode = 36 // kVK_Return

    /// Pastes `text`, then presses Return when `submit` is set (the spoken
    /// "submit"). Empty text with submit just presses Return.
    static func paste(_ text: String, submit: Bool = false) {
        guard !text.isEmpty else {
            if submit { send(returnKey) }
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        // Give the pasteboard server a moment to publish before the shortcut,
        // and the app a moment to take the paste before Return.
        after(0.03) {
            send(vKey, flags: .maskCommand)
            if submit { after(0.12) { send(returnKey) } }
        }
    }

    nonisolated private static func send(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
