import SwiftUI

/// Names and terms the model tends to misspell. They become the model's
/// initial prompt on every dictation (see Settings.initialPrompt).
///
/// No Quiet Native artboard exists for this view; rows follow the
/// Preferences row rhythm.
struct VocabularyView: View {
    @ObservedObject var state: AppState
    @State private var draft = ""

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Words it should know.")
                .font(.system(size: 30, weight: .bold))
            Text("Names and terms Softly gets wrong. They are hinted to the model on every dictation and stay on this Mac.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            HStack(spacing: 10) {
                TextField("Add a word or name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(trimmed.isEmpty)
            }
            .padding(.top, 26)

            VStack(spacing: 0) {
                ForEach(state.vocabulary, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.system(size: 15))
                        Spacer()
                        Button {
                            remove(word)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
            .padding(.top, 16)

            if state.vocabulary.isEmpty {
                Text("No words yet. Softly uses its defaults.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }

            Text("Sent to the model as: “\(Settings.initialPrompt)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 20)
        }
    }

    @MainActor private func add() {
        let word = trimmed
        guard !word.isEmpty else { return }
        if !state.vocabulary.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            state.vocabulary.append(word)
        }
        draft = ""
    }

    @MainActor private func remove(_ word: String) {
        state.vocabulary.removeAll { $0 == word }
    }
}
