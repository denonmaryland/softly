import SwiftUI

/// Download button, progress, or the failure, for when the current speech
/// model is not on disk yet (Home's "To finish" section).
@MainActor
struct ModelDownloadControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.modelDownload {
        case .idle:
            CobaltLink(title: "Download · \(SpeechModel.current.sizeMB) MB", action: state.downloadModel)
        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(Gallery.cobalt)
                    .frame(width: 90)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13))
                    .monospacedDigit()
                CobaltLink(title: "Cancel", weight: .regular, action: state.cancelDownload)
            }
        case .verifying:
            Text("Verifying…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 3) {
                CobaltLink(title: "Try again", action: state.downloadModel)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
        }
    }
}
