import SwiftUI

/// Four rows and a permissions summary. The shortcut and microphone rows
/// are display-only in this version; sounds is the one live toggle.
@MainActor
struct PreferencesView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Make yourself at home.")
                .font(.system(size: 30, weight: .bold))
            Text("A few quiet controls. Everything stays on this Mac.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            VStack(spacing: 0) {
                PreferenceRow(title: "Dictation shortcut", subtitle: "Hold to record · double-tap for hands-free") {
                    Keycap(label: "Right ⌥")
                }
                PreferenceRow(title: "Play sounds", subtitle: "A subtle cue when recording starts and ends") {
                    Toggle("Play sounds", isOn: $state.soundsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                PreferenceRow(title: "Pause music while recording", subtitle: "Music and Spotify pause, then pick up where they left off") {
                    Toggle("Pause music while recording", isOn: $state.pauseMedia)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                PreferenceRow(title: "Microphone", subtitle: "Use the microphone selected in macOS") {
                    Picker("Microphone", selection: .constant(0)) {
                        Text("System default").tag(0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                PreferenceRow(title: "Speech model", subtitle: "English · small model · runs on this Mac") {
                    modelStatus
                }
                PreferenceRow(title: "Updates", subtitle: "Softly \(Updater.currentVersion) · checked quietly every few hours") {
                    updateControl
                }
            }
            .padding(.top, 26)

            permissions
                .padding(.top, 29)
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch state.modelStatus {
        case .ready:
            Text("Loaded on this Mac")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.green)
        case .loading:
            Text("Loading…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .missingModel:
            ModelDownloadControl(state: state)
        case .failed:
            Button("Failed · Reload", action: state.reloadModel)
                .buttonStyle(.link)
                .font(.system(size: 14, weight: .medium))
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch state.update {
        case .idle:
            Button("Check for Updates", action: state.checkForUpdates)
                .buttonStyle(.link)
                .font(.system(size: 14, weight: .medium))
        case .checking:
            Text("Checking…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text("Up to date")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.green)
        case .available(let version):
            Button("Update to \(version)", action: state.installUpdate)
                .buttonStyle(.link)
                .font(.system(size: 14, weight: .semibold))
        case .downloading:
            Text("Downloading…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Button("Try Again", action: state.checkForUpdates)
                    .buttonStyle(.link)
                    .font(.system(size: 14, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption(text: "PERMISSIONS")
            HStack(spacing: 24) {
                PermissionItem(name: "Microphone", granted: state.microphoneGranted) {
                    Permissions.requestMicrophone()
                    Permissions.openSettings("Privacy_Microphone")
                }
                PermissionItem(name: "Input Monitoring", granted: state.inputMonitoringGranted) {
                    Permissions.openSettings("Privacy_ListenEvent")
                }
                PermissionItem(name: "Accessibility", granted: state.accessibilityGranted) {
                    Permissions.openSettings("Privacy_Accessibility")
                }
            }
            if !(state.microphoneGranted && state.inputMonitoringGranted && state.accessibilityGranted) {
                Text("Click a missing one to open System Settings. This window updates as soon as it is granted.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "✓ Name" in green when granted; otherwise a quiet "○ Name" that opens
/// the matching System Settings pane.
private struct PermissionItem: View {
    let name: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        if granted {
            Text("✓ \(name)")
                .font(.system(size: 13))
                .foregroundStyle(Color.green)
        } else {
            Button(action: open) {
                Text("○ \(name)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .help("Open System Settings")
        }
    }
}

/// Download button, progress, or the failure, for the model row and the Home
/// status line. Idle means the file is simply not there yet.
@MainActor
struct ModelDownloadControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.modelDownload {
        case .idle:
            Button("Download speech model (\(ModelDownloader.sizeMB) MB)", action: state.downloadModel)
                .buttonStyle(.link)
                .font(.system(size: 14, weight: .medium))
        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(width: 110)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Cancel", action: state.cancelDownload)
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            }
        case .verifying:
            Text("Verifying…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Button("Download failed · Try again", action: state.downloadModel)
                    .buttonStyle(.link)
                    .font(.system(size: 14, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
    }
}
