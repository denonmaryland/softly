import Foundation

/// Transcribing while you talk: a long recording is cut at natural pauses
/// and each piece is transcribed while you keep speaking, so stopping only
/// leaves the last few seconds to do. Pieces stay under Whisper's 30 s
/// window. Mirrors Windows/Softly.Core/Chunking.cs.
public enum Chunking {
    public static let sampleRate = 16_000
    /// 20 ms analysis windows.
    static let window = 320
    /// Pieces shorter than this are never cut off; short dictations stay whole.
    public static let minimumSeconds = 15.0
    /// Past this, cut at the quietest moment even without a real pause.
    public static let maximumSeconds = 25.0
    /// A pause must be at least this long to cut in.
    static let pauseWindows = 15 // 300 ms
    /// The newest audio is left alone: the speaker may be mid-word.
    static let tailGuard = sampleRate // 1 s

    /// Where to cut `pending` (the audio not yet transcribed), as a sample
    /// count from its start, or nil to keep listening.
    public static func cut(_ pending: [Float]) -> Int? {
        let n = pending.count
        guard Double(n) >= minimumSeconds * Double(sampleRate) else { return nil }
        // Search the second half of the minimum up to the guarded tail.
        let lo = Int(minimumSeconds * 0.5 * Double(sampleRate)) / window
        let hi = (n - tailGuard) / window
        guard hi > lo else { return nil }
        var levels = [Float](repeating: 0, count: hi - lo)
        for w in lo..<hi {
            var sum: Float = 0
            for i in (w * window)..<((w + 1) * window) { sum += pending[i] * pending[i] }
            levels[w - lo] = (sum / Float(window)).squareRoot()
        }
        // Quiet means well below the speech around it, or near-silent outright.
        let sorted = levels.sorted()
        let loud = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        let quiet = max(0.004, loud * 0.15)

        // The latest pause long enough to cut in; cut in its middle.
        var run = 0
        for i in stride(from: levels.count - 1, through: 0, by: -1) {
            if levels[i] < quiet {
                run += 1
            } else {
                if run >= pauseWindows { return (lo + i + 1 + run / 2) * window }
                run = 0
            }
        }
        if run >= pauseWindows { return (lo + run / 2) * window }

        guard Double(n) >= maximumSeconds * Double(sampleRate) else { return nil }
        // No pause: the quietest 100 ms.
        var best = 0
        var bestLevel = Float.greatestFiniteMagnitude
        for i in 0..<max(1, levels.count - 4) {
            let level = levels[i..<min(levels.count, i + 5)].reduce(0, +)
            if level < bestLevel { bestLevel = level; best = i }
        }
        return (lo + best + 2) * window
    }

    /// The loudest 20 ms of `samples`, as RMS: the last piece of a recording
    /// is skipped when it is only silence, which Whisper would invent text for.
    public static func loudest(_ samples: [Float]) -> Float {
        var best: Float = 0
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + window)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            best = max(best, (sum / Float(end - start)).squareRoot())
            start = end
        }
        return best
    }

    /// Joins transcribed pieces in order, skipping ones with nothing said.
    public static func join(_ pieces: [String?]) -> String? {
        let text = pieces.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}
