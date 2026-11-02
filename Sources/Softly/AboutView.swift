import AppKit
import SwiftUI

/// Version and updates, the three permissions, and where things live.
@MainActor
struct AboutView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "About",
                       subtitle: "Free and open source. Your voice and your words never leave this Mac.")

            GallerySection(title: "Softly \(Updater.currentVersion)", detail: "Checked quietly every few hours.", first: true) {
                HStack {
                    updateStatus
                    Spacer(minLength: 0)
                    updateAction
                }
            }

            GallerySection(title: "Permissions", detail: "Click a missing one to open System Settings. This window updates as soon as it is granted.") {
                VStack(spacing: 0) {
                    permission("Microphone", "To hear you", granted: state.microphoneGranted) {
                        Permissions.requestMicrophone()
                        Permissions.openSettings("Privacy_Microphone")
                    }
                    .padding(.top, -14)
                    permission("Input Monitoring", "To notice the dictation key", granted: state.inputMonitoringGranted) {
                        Permissions.openSettings("Privacy_ListenEvent")
                    }
                    permission("Accessibility", "To paste where your cursor is", granted: state.accessibilityGranted, last: true) {
                        Permissions.openSettings("Privacy_Accessibility")
                    }
                }
            }

            GallerySection(title: "On this Mac", detail: "Audio is held in memory and dropped after each dictation.") {
                VStack(spacing: 0) {
                    GalleryRow(title: "Speech models", subtitle: "Downloaded models, in Application Support") {
                        CobaltLink(title: "Show in Finder", action: state.showModelFolder)
                    }
                    .padding(.top, -14)
                    GalleryRow(title: "Source code", subtitle: "github.com/denonmaryland/softly", divider: false) {
                        CobaltLink(title: "Open") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/denonmaryland/softly")!)
                        }
                    }
                }
            }
        }
    }

    private func permission(_ name: String, _ why: String, granted: Bool, last: Bool = false,
                            open: @escaping () -> Void) -> some View {
        GalleryRow(title: name, subtitle: why, divider: !last) {
            if granted {
                Label("Granted", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gallery.ready)
            } else {
                CobaltLink(title: "Open Settings", action: open)
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch state.update {
        case .failed(let message):
            Text(message).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
        case .available(let version):
            Text("Softly \(version) is available.").font(.system(size: 14))
        case .upToDate:
            Text("You have the latest version.").font(.system(size: 14)).foregroundStyle(.secondary)
        default:
            Text("Updates come from GitHub Releases.").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch state.update {
        case .checking:
            Text("Checking…").font(.system(size: 14)).foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading…").font(.system(size: 14)).foregroundStyle(.secondary)
        case .available(let version):
            CobaltLink(title: "Update to \(version)", weight: .semibold, action: state.installUpdate)
        case .upToDate:
            Text("Up to date").font(.system(size: 14, weight: .medium)).foregroundStyle(Gallery.ready)
        case .failed:
            CobaltLink(title: "Try again", action: state.checkForUpdates)
        case .idle:
            CobaltLink(title: "Check for updates", action: state.checkForUpdates)
        }
    }
}
