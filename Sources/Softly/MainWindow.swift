import AppKit
import SwiftUI

/// The app's one ordinary window: Home, Vocabulary and Preferences behind a
/// sidebar (design: Paper "01 Quiet Native", see docs/ui-spec.md).
///
/// The app is menu-bar only, so showing the window has to activate the app,
/// and closing it hands focus back to the app that had it before.
@MainActor
final class MainWindow {
    private let window: NSWindow
    private let state: AppState
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?

    init(state: AppState) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Softly"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 600)
        window.contentViewController = NSHostingController(rootView: MainView(state: state))
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        self.window = window

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.poll() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didClose() }
            },
        ]
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        if !window.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        state.poll()
        startPolling()
    }

    private func didClose() {
        pollTimer?.invalidate()
        pollTimer = nil
        // Return focus to where the user was, as closing a Preferences
        // window of a normal app would. The pill keeps working regardless.
        if let previousApp {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        previousApp = nil
    }

    /// Permission grants happen in System Settings, outside our process, so
    /// poll gently while the window is up.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
