import AppKit
import Foundation

/// Pauses music while recording and resumes only what it paused, like
/// Voxtype's `pause_media` on Linux. Drives Music and Spotify through
/// AppleScript, so macOS asks once per app for Automation permission.
/// Scripts run on a serial queue off the main thread; a slow or stalled
/// player never delays the pill.
final class MediaPauser: @unchecked Sendable {
    static let shared = MediaPauser()

    private struct Player {
        let bundleID: String
        let name: String
    }

    private let players = [
        Player(bundleID: "com.apple.Music", name: "Music"),
        Player(bundleID: "com.spotify.client", name: "Spotify"),
    ]
    private let queue = DispatchQueue(label: "softly.media", qos: .userInitiated)
    /// Names of the players this object paused; only touched on `queue`.
    private var paused: [String] = []

    func pause() {
        guard Settings.pauseMedia else { return }
        // Only apps that are already running are scripted, so nothing launches.
        let running = players.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        guard !running.isEmpty else { return }
        queue.async { [self] in
            paused = []
            for player in running where run("tell application \"\(player.name)\" to player state as text") == "playing" {
                _ = run("tell application \"\(player.name)\" to pause")
                paused.append(player.name)
            }
        }
    }

    func resume() {
        queue.async { [self] in
            let names = paused
            paused = []
            for name in names { _ = run("tell application \"\(name)\" to play") }
        }
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}
