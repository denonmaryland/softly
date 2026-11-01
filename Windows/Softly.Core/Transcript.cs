using System.Text.RegularExpressions;

namespace Softly.Core;

public static class Transcript
{
    private static readonly Regex[] Annotations =
    {
        new(@"\[[^\]]*\]", RegexOptions.Compiled),
        new(@"\([^)]*\)", RegexOptions.Compiled),
        new(@"\*[^*]*\*", RegexOptions.Compiled),
    };
    private static readonly Regex Spaces = new(@"\s+", RegexOptions.Compiled);

    /// <summary>
    /// Joins whisper segments and drops non-speech markers such as
    /// "[BLANK_AUDIO]" or "(silence)". Returns null when nothing was said.
    /// </summary>
    public static string? Clean(IEnumerable<string> segments)
    {
        var kept = new List<string>();
        foreach (var raw in segments)
        {
            string s = raw.Trim();
            foreach (var re in Annotations) s = re.Replace(s, "");
            s = Spaces.Replace(s, " ").Trim();
            if (s.Length > 0) kept.Add(s);
        }
        var text = string.Join(" ", kept);
        return text.Length == 0 ? null : text;
    }

    /// <summary>Whisper rejects very short input; pad with silence to at least 1.1 s.</summary>
    public static float[] Padded(float[] samples, int sampleRate = 16_000)
    {
        int minimum = sampleRate + sampleRate / 10;
        if (samples.Length >= minimum) return samples;
        var padded = new float[minimum];
        samples.CopyTo(padded, 0);
        return padded;
    }
}
