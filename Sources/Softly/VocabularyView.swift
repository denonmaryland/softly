import DictationCore
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

            ReplacementsSection(state: state)
                .padding(.top, 40)
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

/// "When Softly hears this, type that." Applied to every transcript after
/// the model, so a word it keeps getting wrong is fixed every time. An
/// empty "type" removes the phrase (handy for "um" and "uh").
private struct ReplacementsSection: View {
    @ObservedObject var state: AppState
    @State private var heard = ""
    @State private var typed = ""

    private var heardTrimmed: String { heard.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fix what it hears.")
                .font(.system(size: 22, weight: .bold))
            Text("When Softly hears the phrase on the left, it types the one on the right. Leave the right side empty to drop a word, like “um”.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            HStack(spacing: 10) {
                TextField("Heard, e.g. cloud code", text: $heard)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .onSubmit { add() }
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Type, e.g. Claude Code", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(heardTrimmed.isEmpty)
            }
            .padding(.top, 20)

            VStack(spacing: 0) {
                ForEach(state.replacements, id: \.self) { rule in
                    HStack(spacing: 10) {
                        Text(rule.from)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(rule.to.isEmpty ? "(removed)" : rule.to)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(rule.to.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button {
                            state.replacements.removeAll { $0 == rule }
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

            if state.replacements.isEmpty {
                Text("No fixes yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
        }
    }

    @MainActor private func add() {
        let from = heardTrimmed
        guard !from.isEmpty else { return }
        let rule = Replacement(from: from, to: typed.trimmingCharacters(in: .whitespacesAndNewlines))
        // A new fix for the same phrase replaces the old one.
        state.replacements.removeAll { $0.from.caseInsensitiveCompare(from) == .orderedSame }
        state.replacements.append(rule)
        heard = ""
        typed = ""
    }
}
