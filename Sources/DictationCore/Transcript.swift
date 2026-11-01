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
        return text.isEmpty ? nil : text
    }

    /// Whisper rejects very short input; pad with silence to at least one second.
    public static func padded(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        let minimum = sampleRate + sampleRate / 10
        guard samples.count < minimum else { return samples }
        return samples + [Float](repeating: 0, count: minimum - samples.count)
    }
}
