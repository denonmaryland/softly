import AppKit

/// The same short open/close cues as the Linux pill (Resources/Sounds).
@MainActor
enum Sounds {
    private static let open = load("open")
    private static let close = load("close")

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }

    static func playOpen() { play(open) }
    static func playClose() { play(close) }

    private static func play(_ sound: NSSound?) {
        guard Settings.soundsEnabled, let sound else { return }
        sound.stop()
        sound.play()
    }
}
