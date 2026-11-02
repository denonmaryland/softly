import Foundation

/// Recognition settings mirror the Linux Voxtype config (small.en Q5_1,
/// English, flash attention, four threads, custom vocabulary prompt).
enum Settings {
    static let appName = "Softly"
    static let modelFileName = "ggml-small.en-q5_1.bin"
    static let language = "en"
    /// Names the model otherwise misspells, edited in the window's Vocabulary
    /// view. Empty on first run; each person adds their own.
    static let defaultVocabulary: [String] = []
    static let threads: Int32 = 4
    /// Recording cap (15 minutes), same as Voxtype's max_duration_secs.
    static let maxDuration: TimeInterval = 900
    /// Recordings shorter than this are treated as accidental taps.
    static let minimumSpeech: TimeInterval = 0.25
    /// Recordings whose loudest moment stays below this RMS are skipped as silence.
    static let silenceRMS: Double = 0.005

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var modelDirectory: URL { supportDirectory.appendingPathComponent("Models", isDirectory: true) }

    /// Where the model lived before the app was renamed from Quiet Dictation.
    private static var legacyModelURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuietDictation/Models/\(modelFileName)")
    }

    /// A model bundled in the app's Resources wins; otherwise Application
    /// Support, falling back to the pre-rename folder.
    static var modelURL: URL {
        if let bundled = Bundle.main.url(forResource: modelFileName, withExtension: nil) { return bundled }
        let current = modelDirectory.appendingPathComponent(modelFileName)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        if FileManager.default.fileExists(atPath: legacyModelURL.path) { return legacyModelURL }
        return current
    }

    static var soundsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
    }

    /// Pause Music and Spotify while recording, resuming them afterwards.
    static var pauseMedia: Bool {
        get { UserDefaults.standard.object(forKey: "pauseMedia") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pauseMedia") }
    }

    static var vocabulary: [String] {
        get { UserDefaults.standard.stringArray(forKey: "vocabulary") ?? defaultVocabulary }
        set { UserDefaults.standard.set(newValue, forKey: "vocabulary") }
    }

    /// The vocabulary as Whisper's initial prompt; empty when there are no words.
    static var initialPrompt: String {
        let words = vocabulary
        return words.isEmpty ? "" : words.joined(separator: ", ") + "."
    }
}
