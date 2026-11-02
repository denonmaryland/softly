import SwiftUI

/// Status, the one gesture to learn, and a scratch box to try it in.
@MainActor
struct HomeView: View {
    @ObservedObject var state: AppState
    @State private var practice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine

            Text("Your words. Right where you need them.")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 14)
            Text("Speak into the app you’re using. Softly takes it from here.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            shortcutCard
                .padding(.top, 50)

            Text("Try it here")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 45)

            practiceBox
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Runs on this Mac. No audio saved. No transcript history.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.8))
                Text("Esc cancels · Your transcript stays on the clipboard after pasting.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 29)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.ready ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(state.ready ? "Ready to dictate" : state.statusLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.ready ? Color.green : Color.secondary)
            if state.modelStatus == .missingModel {
                ModelDownloadControl(state: state)
                    .padding(.leading, 10)
            }
        }
    }

    private var shortcutCard: some View {
        HStack(spacing: 26) {
            Keycap(label: state.hotkey.label)
            VStack(alignment: .leading, spacing: 6) {
                Text("Hold to speak. Release to paste.")
                    .font(.system(size: 18, weight: .semibold))
                Text(state.tapToStart ? "Tap to start, tap again to finish. Or hold to talk." : "Hold the key while you talk, then let go.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// A plain text view. Dictating while it has focus pastes here like in
    /// any other app; nothing is kept.
    private var practiceBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $practice)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                if practice.isEmpty {
                    Text("Click here, then hold \(state.hotkey.name) and say something.")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Text("A temporary place to get comfortable.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { practice = "" }
                    .controlSize(.small)
                    .disabled(practice.isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(height: 154)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
