import Foundation

/// "When Softly hears this, type that." One saved rule.
public struct Replacement: Codable, Equatable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Fixes the words recognition keeps getting wrong, after transcription:
/// "cloud code" becomes "Claude Code". Matching ignores case and only takes
/// whole words, so "omarch" does not fire inside "omarchy". Spaces in a
/// rule match any run of spaces or hyphens. An empty `to` deletes the
/// phrase, which is how filler words like "um" are dropped. Mirrors
/// Windows/Softly.Core/Replacements.cs; Voxtype's text.replacements does
/// the same job on Linux.
public enum Replacements {
    public static func apply(_ text: String, _ rules: [Replacement]) -> String {
        var seen: [String: Int] = [:]
        var usable: [Replacement] = []
        for rule in rules {
            let from = collapse(rule.from, #"\s+"#)
            guard !from.isEmpty else { continue }
            let cleaned = Replacement(from: from, to: rule.to.trimmingCharacters(in: .whitespacesAndNewlines))
            if let index = seen[key(from)] {
                usable[index] = cleaned // the later rule wins
            } else {
                seen[key(from)] = usable.count
                usable.append(cleaned)
            }
        }
        // Longest first, so "cloud code" wins over "cloud".
        usable.sort { $0.from.count > $1.from.count }
        guard !usable.isEmpty, !text.isEmpty else { return text }

        var byKey: [String: String] = [:]
        for rule in usable where byKey[key(rule.from)] == nil { byKey[key(rule.from)] = rule.to }
        let alternatives = usable.map { rule in
            rule.from.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"[\s-]+"#)
        }
        let pattern = #"(?<![\p{L}\p{N}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let source = text as NSString
        var result = ""
        var last = 0
        var deleted = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let found = source.substring(with: match.range)
            let to = byKey[key(found)] ?? found
            if to.isEmpty { deleted = true }
            result += source.substring(with: NSRange(location: last, length: match.range.location - last)) + to
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return deleted ? tidy(result, original: text) : result
    }

    /// Lowercased, with spaces and hyphens folded to one space.
    private static func key(_ phrase: String) -> String {
        collapse(phrase.lowercased(), #"[\s-]+"#)
    }

    private static func collapse(_ text: String, _ pattern: String) -> String {
        text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Done. so" reads "Done. So" once the "um" between them is gone.
    private static func capitalizeAfterStops(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[.!?]\s+\p{Ll}"#) else { return text }
        let source = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let last = NSRange(location: match.range.location + match.range.length - 1, length: 1)
            result = (result as NSString).replacingCharacters(in: last, with: source.substring(with: last).uppercased())
        }
        return result
    }

    /// Cleans up after a deleted word: "So, um, yes" reads "So, yes".
    private static func tidy(_ text: String, original: String) -> String {
        var s = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.!?])[,;:]+"#, with: "$1", options: .regularExpression)
        s = capitalizeAfterStops(s)
        s = s.replacingOccurrences(of: #"^[\s,;:.!?]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let startedLower = original.trimmingCharacters(in: .whitespaces).first?.isLowercase ?? true
        if let first = s.first, first.isLowercase, !startedLower {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }
}
