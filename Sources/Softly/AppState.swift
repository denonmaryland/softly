import AppKit
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
    @Published var vocabulary = Settings.vocabulary {
        didSet { Settings.vocabulary = vocabulary }
    }
    @Published var update: Updater.State = .idle
    @Published var modelDownload: ModelDownloader.State = .idle

    /// Wired by the delegate; views only call them.
    var showModelFolder: () -> Void = {}
    var reloadModel: () -> Void = {}
    var downloadModel: () -> Void = {}
    var cancelDownload: () -> Void = {}
    var previewPill: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var installUpdate: () -> Void = {}
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
            return "Ready: hold Right ⌥ to dictate"
        }
    }
}
