import Foundation

public enum Transcript {
    /// Joins whisper segments and drops non-speech markers such as
    /// "[BLANK_AUDIO]" or "(silence)". Returns nil when nothing was said.
    public static func clean(_ segments: [String]) -> String? {
        let kept = segments.compactMap { raw -> String? in
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove bracketed annotations: [BLANK_AUDIO], (wind), [ Silence ], *music*.
            for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"\*[^*]*\*"#] {
                s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        let text = kept.joined(separator: " ")
        return text.isEmpty || isSilencePhrase(text) ? nil : text
    }

    /// Whisper was trained partly on video subtitles, so near-silence often
    /// comes back as one of these. Only a transcript that is nothing but one
    /// of them is dropped; the same words inside real speech are kept.
    static let silencePhrases: Set<String> = [
        "thanks for watching",
        "thanks for watching bye",
        "thank you for watching",
        "thank you so much for watching",
        "thanks for listening",
        "thank you for listening",
        "please subscribe",
        "please like and subscribe",
        "like and subscribe",
        "subscribe to my channel",
        "dont forget to like and subscribe",
        "see you in the next video",
        "see you next time",
        "bye",
        "bye bye", "byebye",
        "you",
        "subtitles by the amaraorg community",
        "transcription by castingwords",
    ]

    public static func isSilencePhrase(_ text: String) -> Bool {
        let letters = text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let normalized = String(String.UnicodeScalarView(letters))
            .split(separator: " ").joined(separator: " ")
        return silencePhrases.contains(normalized)
    }

    /// Whisper rejects very short input; pad with silence to at least one second.
    public static func padded(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        let minimum = sampleRate + sampleRate / 10
        guard samples.count < minimum else { return samples }
        return samples + [Float](repeating: 0, count: minimum - samples.count)
    }
}
