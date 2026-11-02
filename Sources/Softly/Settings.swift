import Foundation

import DictationCore

/// Recognition settings mirror the Linux Voxtype config (English, flash
/// attention, four threads, custom vocabulary prompt). The model is picked
/// in Preferences from SpeechModel.all.
enum Settings {
    static let appName = "Softly"
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

    /// Id of the speech model in use, from SpeechModel.all.
    static var speechModel: String {
        get { UserDefaults.standard.string(forKey: "speechModel") ?? SpeechModel.balanced.id }
        set { UserDefaults.standard.set(newValue, forKey: "speechModel") }
    }

    static var modelURL: URL { SpeechModel.current.fileURL }

    static var soundsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
    }

    /// Pause Music and Spotify while recording, resuming them afterwards.
    static var pauseMedia: Bool {
        get { UserDefaults.standard.object(forKey: "pauseMedia") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pauseMedia") }
    }

    /// Tap once to start hands-free and again to finish. Off is hold-only.
    static var tapToStart: Bool {
        get { UserDefaults.standard.object(forKey: "tapToStart") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tapToStart") }
    }

    /// The pill's style, an id from PillTheme.all.
    /// Virtual key code of the dictation key; Right Option by default.
    static var hotkeyCode: Int64 {
        get { (UserDefaults.standard.object(forKey: "hotkeyCode") as? NSNumber)?.int64Value ?? 61 }
        set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: "hotkeyCode") }
    }

    static var pillTheme: String {
        get { UserDefaults.standard.string(forKey: "pillTheme") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "pillTheme") }
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

    /// "Heard this, type that" fixes applied after transcription.
    static var replacements: [Replacement] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "replacements"),
                  let rules = try? JSONDecoder().decode([Replacement].self, from: data) else { return [] }
            return rules
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "replacements") }
    }
}
