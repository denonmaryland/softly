import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel: it floats over every Space
/// and full-screen app but never becomes key, so the app you are dictating
/// into keeps focus and receives the paste.
@MainActor
final class PillPanel: NSPanel {
    static func make(model: PillModel) -> PillPanel {
        let panel = PillPanel(
            contentRect: NSRect(origin: .zero, size: PillGeometry.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.configure(model: model)
        return panel
    }

    private func configure(model: PillModel) {
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the pill draws its own shadows
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let host = FirstClickHostingView(rootView: PillView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: PillGeometry.panelSize)
        contentView = host

        model.pointerLocation = { [weak self] in self?.pointerInPill() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom-centre of the screen under the pointer, above the Dock.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: (visible.midX - PillGeometry.panelSize.width / 2).rounded(),
                y: visible.minY + PillGeometry.bottomMargin
            ))
        }
        orderFrontRegardless()
    }

    /// Polled each frame: hover works even though this app is never active.
    private func pointerInPill() -> CGPoint? {
        guard isVisible else { return nil }
        let p = NSEvent.mouseLocation
        guard NSMouseInRect(p, frame, false) else { return nil }
        return CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y) // flip to top-left origin
    }
}

/// Lets the first click reach the pill without activating the app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
