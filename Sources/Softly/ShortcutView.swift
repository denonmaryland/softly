import SwiftUI

/// The dictation key, tap or hold, and what happens around a dictation.
@MainActor
struct ShortcutView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Shortcut",
                       subtitle: "How you start and stop, and what happens around a dictation.")

            GallerySection(title: "Key", detail: "Esc cancels while the pill is up.", first: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        if state.capturingHotkey {
                            Text("Press a key…")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Gallery.cobalt)
                                .padding(.vertical, 10)
                        } else {
                            Keycap(label: state.hotkey.label, large: true)
                        }
                        Text(state.hotkeyNote ?? "Right ⌘, Right ⌃ or a function key also work")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        CobaltLink(title: state.capturingHotkey ? "Cancel" : "Change") {
                            if state.capturingHotkey { state.cancelCapture() } else { state.captureHotkey() }
                        }
                    }
                    .padding(.bottom, 16)
                    Rectangle().fill(Gallery.hairline).frame(height: 1)
                    GalleryRow(title: "Tap to start and stop",
                               subtitle: "Off: hold the key while you talk, let go to finish",
                               divider: false) {
                        GallerySwitch(label: "Tap to start and stop", isOn: $state.tapToStart)
                    }
                }
            }

            GallerySection(title: "While you talk", detail: "What Softly does around a dictation.") {
                VStack(spacing: 0) {
                    GalleryRow(title: "Microphone", subtitle: "Recording is capped at 15 minutes") {
                        Picker("Microphone", selection: $state.microphone) {
                            Text("System default").tag("")
                            ForEach(state.microphones) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .padding(.top, -14)
                    GalleryRow(title: "Pause music", subtitle: "Music and Spotify pick up where they left off") {
                        GallerySwitch(label: "Pause music", isOn: $state.pauseMedia)
                    }
                    GalleryRow(title: "Sounds", subtitle: "A soft cue when recording starts and ends", divider: false) {
                        GallerySwitch(label: "Sounds", isOn: $state.soundsEnabled)
                    }
                }
            }
        }
        // A capture left running would quietly take the next key pressed elsewhere.
        .onDisappear { if state.capturingHotkey { state.cancelCapture() } }
        .onAppear { state.refreshMicrophones() }
    }
}
