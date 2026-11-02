namespace Softly.Core;

/// <summary>
/// Transcribing while you talk: a long recording is cut at natural pauses
/// and each piece is transcribed while you keep speaking, so stopping only
/// leaves the last few seconds to do. Pieces stay under Whisper's 30 s
/// window. Mirrors Sources/DictationCore/Chunking.swift.
/// </summary>
public static class Chunking
{
    public const int SampleRate = 16_000;
    /// <summary>20 ms analysis windows.</summary>
    private const int Window = 320;
    /// <summary>Pieces shorter than this are never cut off; short dictations stay whole.</summary>
    public const double MinimumSeconds = 15;
    /// <summary>Past this, cut at the quietest moment even without a real pause.</summary>
    public const double MaximumSeconds = 25;
    /// <summary>A pause must be at least this long (300 ms) to cut in.</summary>
    private const int PauseWindows = 15;
    /// <summary>The newest second is left alone: the speaker may be mid-word.</summary>
    private const int TailGuard = SampleRate;

    /// <summary>
    /// Where to cut <paramref name="pending"/> (the audio not yet transcribed),
    /// as a sample count from its start, or null to keep listening.
    /// </summary>
    public static int? Cut(IReadOnlyList<float> pending)
    {
        int n = pending.Count;
        if (n < MinimumSeconds * SampleRate) return null;
        // Search the second half of the minimum up to the guarded tail.
        int lo = (int)(MinimumSeconds * 0.5 * SampleRate) / Window;
        int hi = (n - TailGuard) / Window;
        if (hi <= lo) return null;
        var levels = new float[hi - lo];
        for (int w = lo; w < hi; w++)
        {
            float sum = 0;
            for (int i = w * Window; i < (w + 1) * Window; i++) sum += pending[i] * pending[i];
            levels[w - lo] = MathF.Sqrt(sum / Window);
        }
        // Quiet means well below the speech around it, or near-silent outright.
        var sorted = levels.OrderBy(l => l).ToArray();
        float loud = sorted[Math.Min(sorted.Length - 1, sorted.Length * 9 / 10)];
        float quiet = MathF.Max(0.004f, loud * 0.15f);

        // The latest pause long enough to cut in; cut in its middle.
        int run = 0;
        for (int i = levels.Length - 1; i >= 0; i--)
        {
            if (levels[i] < quiet) { run++; continue; }
            if (run >= PauseWindows) return (lo + i + 1 + run / 2) * Window;
            run = 0;
        }
        if (run >= PauseWindows) return (lo + run / 2) * Window;

        if (n < MaximumSeconds * SampleRate) return null;
        // No pause: the quietest 100 ms.
        int best = 0;
        float bestLevel = float.MaxValue;
        for (int i = 0; i < Math.Max(1, levels.Length - 4); i++)
        {
            float level = 0;
            for (int k = i; k < Math.Min(levels.Length, i + 5); k++) level += levels[k];
            if (level < bestLevel) { bestLevel = level; best = i; }
        }
        return (lo + best + 2) * Window;
    }

    /// <summary>
    /// The loudest 20 ms of <paramref name="samples"/>, as RMS: the last piece of a
    /// recording is skipped when it is only silence, which Whisper would invent text for.
    /// </summary>
    public static float Loudest(IReadOnlyList<float> samples)
    {
        float best = 0;
        for (int start = 0; start < samples.Count; start += Window)
        {
            int end = Math.Min(samples.Count, start + Window);
            float sum = 0;
            for (int i = start; i < end; i++) sum += samples[i] * samples[i];
            best = MathF.Max(best, MathF.Sqrt(sum / (end - start)));
        }
        return best;
    }

    /// <summary>Joins transcribed pieces in order, skipping ones with nothing said.</summary>
    public static string? Join(IEnumerable<string?> pieces)
    {
        var text = string.Join(" ", pieces.Where(p => !string.IsNullOrEmpty(p)));
        return text.Length == 0 ? null : text;
    }
}
