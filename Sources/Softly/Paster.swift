import AppKit
import CoreGraphics

/// Puts the transcript on the clipboard and sends ⌘V to the frontmost app.
/// Like the Linux helper, the transcript stays on the clipboard afterwards,
/// so it can be pasted again if the field didn't accept it.
@MainActor
enum Paster {
    nonisolated private static let vKey: CGKeyCode = 9 // kVK_ANSI_V

    static func paste(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        // Give the pasteboard server a moment to publish before the shortcut.
        after(0.03) { sendCommandV() }
    }

    nonisolated private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
