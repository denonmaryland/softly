import SwiftUI

/// Status, a box to try the key in, and the last few dictations.
@MainActor
struct HomeView: View {
    @ObservedObject var state: AppState
    @State private var practice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: state.ready ? "Ready" : starting ? "Starting" : "Almost ready",
                subtitle: state.ready
                    ? "Tap \(state.hotkey.label) anywhere, talk, and tap again. The words land where your cursor is."
                    : state.statusLine
            )

            if !state.ready && !starting {
                setup
            }

            GallerySection(title: "Try it here", first: state.ready || starting, aside: AnyView(
                HStack(spacing: 8) {
                    Keycap(label: state.hotkey.label)
                    Text(state.tapToStart ? "tap or hold" : "hold")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            )) {
                practiceBox
            }

            GallerySection(title: "Recent", detail: "The last five, kept in memory only. Gone when Softly quits.") {
                recent
            }
        }
    }

    /// Only the model is still loading; nothing for the user to do.
    private var starting: Bool {
        state.modelStatus == .loading && state.microphoneGranted && state.hotkeysRunning
    }

    /// What is still missing, with the one button that fixes it.
    @ViewBuilder
    private var setup: some View {
        GallerySection(title: "To finish", detail: "Softly needs these once.", first: true) {
            VStack(alignment: .leading, spacing: 0) {
                if state.modelStatus == .missingModel {
                    GalleryRow(title: "Speech model", subtitle: "Downloads once, then runs on this Mac") {
                        ModelDownloadControl(state: state)
                    }
                }
                if !(state.microphoneGranted && state.inputMonitoringGranted && state.accessibilityGranted) {
                    GalleryRow(title: "Permissions", subtitle: "Microphone, Input Monitoring and Accessibility", divider: false) {
                        CobaltLink(title: "Open About") { state.section = .about }
                    }
                }
            }
        }
    }

    /// A plain text view. Dictating while it has focus pastes here like in
    /// any other app; nothing is kept.
    private var practiceBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $practice)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                if practice.isEmpty {
                    Text("Click here, tap \(state.hotkey.label) and say something…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                if practice.isEmpty {
                    Text("Only a test box. Nothing is kept.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    CobaltLink(title: "Clear") { practice = "" }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(height: 112)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Gallery.well))
    }

    @ViewBuilder
    private var recent: some View {
        if state.recent.isEmpty {
            Text("Nothing yet. What you dictate shows up here so you can copy it again.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(state.recent.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 16) {
                        Text(item.text)
                            .font(.system(size: 14))
                            .foregroundStyle(index == 0 ? Color.primary : Color.primary.opacity(0.8))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                        CobaltLink(title: "Copy") { state.copy(item.text) }
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    if index < state.recent.count - 1 {
                        Rectangle().fill(Gallery.hairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, -10)
        }
    }
}
