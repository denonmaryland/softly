import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

@MainActor
enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// The hotkey tap needs Input Monitoring; posting ⌘V and swallowing Esc need Accessibility.
    static var keyboardGranted: Bool { inputMonitoringGranted && accessibilityGranted }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestKeyboard() {
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
