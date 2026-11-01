import AppKit

@main
enum SoftlyMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar only: no Dock icon, never steals focus from the app you dictate into.
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}
