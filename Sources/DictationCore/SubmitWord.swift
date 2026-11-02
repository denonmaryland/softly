import Foundation

/// "…and fix the test, submit." Ending a dictation with the word "submit"
/// strips it and asks for Enter after the paste, so a prompt goes to an agent
/// hands-free. Only a final, whole "submit" counts: "resubmit" and a
/// "submit" mid-sentence are left alone. Mirrors Windows/Softly.Core/SubmitWord.cs
/// and Linux/plugin/bin/softly-fix.
public enum SubmitWord {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^(.*?)[\s,.;:!?-]*(?<![\p{L}\p{N}])submit[\s.!?]*$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    public static func split(_ text: String) -> (text: String, submit: Bool) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let body = Range(match.range(at: 1), in: text) else { return (text, false) }
        return (String(text[body]).trimmingCharacters(in: .whitespacesAndNewlines), true)
    }
}
