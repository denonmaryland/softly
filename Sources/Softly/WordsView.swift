import DictationCore
import SwiftUI

/// Vocabulary hints and "heard this, type that" fixes.
@MainActor
struct WordsView: View {
    @ObservedObject var state: AppState
    @State private var newWord = ""
    @State private var heard = ""
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Words",
                       subtitle: "Names Softly should know, and fixes for what it keeps mishearing.")

            GallerySection(title: "Vocabulary",
                           detail: "Names the model should listen for on every dictation.",
                           first: true) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(state.vocabulary, id: \.self) { word in
                        HStack(spacing: 6) {
                            Text(word).font(.system(size: 14))
                            Button {
                                state.vocabulary.removeAll { $0 == word }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help("Remove")
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 12)
                        .padding(.trailing, 9)
                        .background(Capsule().fill(Gallery.well))
                    }
                    TextField("+ Add a word", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .frame(width: 120)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .onSubmit(addWord)
                }
            }

            GallerySection(title: "Fixes",
                           detail: "When Softly hears the left, it types the right. Leave the right empty to drop a word.") {
                fixes
            }
        }
    }

    private var fixes: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("HEARD").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 16, height: 1)
                Text("TYPES").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 24, height: 1)
            }
            .font(.system(size: 12))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(state.replacements, id: \.self) { rule in
                Rectangle().fill(Gallery.hairline).frame(height: 1)
                HStack(spacing: 12) {
                    Text(rule.from)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                    Group {
                        if rule.to.isEmpty {
                            Text("removed").italic().foregroundStyle(.tertiary)
                        } else {
                            Text(rule.to).fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        state.replacements.removeAll { $0 == rule }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
                    .help("Remove")
                }
                .font(.system(size: 14))
                .padding(.vertical, 10)
            }

            Rectangle().fill(Gallery.hairline).frame(height: 1)
            HStack(spacing: 12) {
                field("Heard…", text: $heard)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                field("Types…", text: $typed)
                Button(action: addFix) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(heardTrimmed.isEmpty ? Color.secondary.opacity(0.4) : Gallery.cobalt))
                }
                .buttonStyle(.plain)
                .disabled(heardTrimmed.isEmpty)
                .help("Add fix")
            }
            .padding(.top, 10)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .frame(maxWidth: .infinity)
            .onSubmit(addFix)
    }

    private var heardTrimmed: String { heard.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        newWord = ""
        guard !word.isEmpty,
              !state.vocabulary.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        state.vocabulary.append(word)
    }

    private func addFix() {
        let from = heardTrimmed
        guard !from.isEmpty else { return }
        // A new fix for the same phrase replaces the old one.
        state.replacements.removeAll { $0.from.caseInsensitiveCompare(from) == .orderedSame }
        state.replacements.append(Replacement(from: from, to: typed.trimmingCharacters(in: .whitespacesAndNewlines)))
        heard = ""
        typed = ""
    }
}
