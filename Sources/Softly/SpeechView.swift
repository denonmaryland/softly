import DictationCore
import SwiftUI

/// Model, language and the spoken "submit".
@MainActor
struct SpeechView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Speech",
                       subtitle: "How Softly hears you. Everything runs on this Mac; nothing is sent anywhere.")

            GallerySection(title: "Model", detail: "Bigger hears names and code better. Others download once.", first: true) {
                VStack(spacing: 0) {
                    ForEach(Array(SpeechModel.all.enumerated()), id: \.element.id) { index, model in
                        ModelRow(state: state, model: model, last: index == SpeechModel.all.count - 1)
                    }
                }
                .padding(.top, -12)
            }

            GallerySection(title: "Language", detail: state.speechModel == SpeechModel.parakeet.id
                           ? "Parakeet detects the language itself."
                           : "What you speak.") {
                languages
            }

            GallerySection(title: "Say “submit”", detail: "For agents and chats.") {
                HStack(spacing: 24) {
                    (Text("End with “submit” and Softly presses Enter after pasting. ")
                        + Text("“…and rerun the tests, submit.”").foregroundColor(.secondary))
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    GallerySwitch(label: "Say submit to send", isOn: $state.submitWord)
                }
            }
        }
    }

    /// English and Detect as pills; every other language behind "More".
    private var languages: some View {
        let others = Languages.all.filter { $0.code != "en" && $0.code != "auto" }
        let picked = others.first { $0.code == state.language }
        return HStack(spacing: 8) {
            ChoicePill(selected: state.language == "en", action: { state.chooseLanguage("en") }) { Text("English") }
            ChoicePill(selected: state.language == "auto", action: { state.chooseLanguage("auto") }) { Text("Detect") }
            Menu {
                ForEach(others, id: \.code) { language in
                    Button(language.name) { state.chooseLanguage(language.code) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(picked?.name ?? "\(others.count) more")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 14, weight: picked == nil ? .regular : .medium))
                .foregroundStyle(picked == nil ? Color.secondary : Color(nsColor: .textBackgroundColor))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Capsule().fill(picked == nil ? Color.clear : Color.primary))
                .overlay(Capsule().stroke(picked == nil ? Gallery.hairline : Color.clear, lineWidth: 1))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// Radio, name and a short note, and on the right its state: in use,
/// downloaded, a download progress bar, or the size to get it.
private struct ModelRow: View {
    @ObservedObject var state: AppState
    let model: SpeechModel
    let last: Bool

    private var selected: Bool { model.id == state.speechModel }
    private var fetching: Bool { state.downloadingModel == model.id }

    private var note: String {
        switch model.id {
        case "fast": return "Smallest and quickest"
        case "balanced": return "Quick, good with everyday speech"
        case "accurate": return "Best with names and code"
        default: return "Fastest on Apple silicon · no hints"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if fetching, case .downloading = state.modelDownload {
                    state.cancelDownload()
                } else if !selected {
                    state.chooseModel(model.id)
                }
            } label: {
                HStack(spacing: 14) {
                    Circle()
                        .strokeBorder(selected ? Gallery.cobalt : Color.primary.opacity(0.3), lineWidth: selected ? 5 : 1.5)
                        .frame(width: 18, height: 18)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.name)
                            .font(.system(size: 15, weight: selected ? .semibold : .medium))
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    trailing
                        .frame(width: 130, alignment: .trailing)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last {
                Rectangle().fill(Gallery.hairline).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if fetching, case .downloading(let progress) = state.modelDownload {
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(Gallery.cobalt)
                    .frame(width: 64)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13))
                    .monospacedDigit()
            }
            .help("Click to cancel")
        } else if fetching, state.modelDownload == .verifying {
            Text("Verifying…").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if fetching, case .failed = state.modelDownload {
            Text("Failed · Retry").font(.system(size: 13, weight: .medium)).foregroundStyle(Gallery.cobalt)
        } else if selected {
            Text(state.modelStatus == .loading ? "Loading…" : "In use")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Gallery.cobalt)
        } else if model.isDownloaded {
            Text("Downloaded").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            Text("Get · \(model.sizeMB) MB").font(.system(size: 13, weight: .medium)).foregroundStyle(Gallery.cobalt)
        }
    }
}
