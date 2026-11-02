import AppKit
import DictationCore
import Combine

/// What the window and the menu-bar menu show: model status, permissions
/// and the two user settings. The delegate refreshes it whenever something
/// changes; the window polls it while visible so permission grants made in
/// System Settings show up without a relaunch.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var modelStatus: Transcriber.Status = .loading
    @Published private(set) var hotkeysRunning = false
    @Published private(set) var microphoneGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var accessibilityGranted = false

    @Published var soundsEnabled = Settings.soundsEnabled {
        didSet { Settings.soundsEnabled = soundsEnabled }
    }
    @Published var pauseMedia = Settings.pauseMedia {
        didSet { Settings.pauseMedia = pauseMedia }
    }
    @Published var tapToStart = Settings.tapToStart {
        didSet { Settings.tapToStart = tapToStart }
    }
    @Published var submitWord = Settings.submitWord {
        didSet { Settings.submitWord = submitWord }
    }
    @Published var hotkey = Hotkey.current {
        didSet { Settings.hotkeyCode = hotkey.keyCode; applyHotkey(hotkey) }
    }
    /// Waiting for the user to press the new dictation key.
    @Published var capturingHotkey = false
    /// Shown under the shortcut row after an unusable key.
    @Published var hotkeyNote: String?
    @Published var pillTheme = Settings.pillTheme {
        didSet { Settings.pillTheme = pillTheme }
    }
    @Published var vocabulary = Settings.vocabulary {
        didSet { Settings.vocabulary = vocabulary }
    }
    @Published var replacements = Settings.replacements {
        didSet { Settings.replacements = replacements }
    }
    /// Saved by the delegate once the model is on disk; pick with chooseModel.
    @Published var speechModel = Settings.speechModel {
        didSet { Settings.speechModel = speechModel }
    }
    /// Whisper language code; pick with chooseLanguage.
    @Published var language = Settings.language {
        didSet { Settings.language = language }
    }
    /// Id of the model being downloaded, if any.
    @Published var downloadingModel: String?
    @Published var update: Updater.State = .idle
    /// The window's current screen; the delegate jumps to a screen too.
    @Published var section: WindowSection = .home
    /// The last few dictations, newest first. Memory only, like the engine's.
    @Published private(set) var recent: [RecentDictation] = []
    /// Unique ID of the chosen microphone; empty follows the system default.
    @Published var microphone = Settings.microphone {
        didSet { Settings.microphone = microphone }
    }
    @Published private(set) var microphones: [Microphones.Device] = []
    @Published var modelDownload: ModelDownloader.State = .idle

    /// Wired by the delegate; views only call them.
    var showModelFolder: () -> Void = {}
    var reloadModel: () -> Void = {}
    var downloadModel: () -> Void = {}
    var cancelDownload: () -> Void = {}
    var chooseModel: (String) -> Void = { _ in }
    var chooseLanguage: (String) -> Void = { _ in }
    var previewPill: () -> Void = {}
    var applyHotkey: (Hotkey) -> Void = { _ in }
    var captureHotkey: () -> Void = {}
    var cancelCapture: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var installUpdate: () -> Void = {}
    func addRecent(_ text: String) {
        recent = [RecentDictation(text: text, date: Date())] + recent.filter { $0.text != text }.prefix(4)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func refreshMicrophones() {
        update(\.microphones, Microphones.all())
    }

    /// Asks the delegate to re-read engine and hotkey state into this object.
    var poll: () -> Void = {}

    func refresh(modelStatus: Transcriber.Status, hotkeysRunning: Bool) {
        update(\.modelStatus, modelStatus)
        update(\.hotkeysRunning, hotkeysRunning)
        update(\.microphoneGranted, Permissions.microphoneGranted)
        update(\.inputMonitoringGranted, Permissions.inputMonitoringGranted)
        update(\.accessibilityGranted, Permissions.accessibilityGranted)
    }

    /// Only publishes when the value actually changed, so polling is quiet.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Everything needed to dictate is in place.
    var ready: Bool { modelStatus == .ready && hotkeysRunning && microphoneGranted }

    /// One line for the menu and the Home status; same wording in both places.
    var statusLine: String {
        switch modelStatus {
        case .loading: return "Loading speech model…"
        case .missingModel:
            switch modelDownload {
            case .downloading(let progress): return "Downloading speech model… \(Int(progress * 100))%"
            case .verifying: return "Verifying speech model…"
            case .failed: return "Speech model download failed"
            case .idle: return "Speech model not downloaded yet"
            }
        case .failed: return "Model failed to load"
        case .ready:
            if !hotkeysRunning { return "Waiting for keyboard permissions" }
            if !microphoneGranted { return "Waiting for microphone permission" }
            return "Ready: \(tapToStart ? "tap" : "hold") \(hotkey.label) to dictate"
        }
    }
}

struct RecentDictation: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}
