using System.Text.RegularExpressions;

namespace Softly.Core;

/// <summary>"When Softly hears this, type that." One saved rule.</summary>
public sealed record Replacement(string From, string To);

/// <summary>
/// Fixes the words recognition keeps getting wrong, after transcription:
/// "cloud code" becomes "Claude Code". Matching ignores case and only takes
/// whole words, so "omarch" does not fire inside "omarchy". Spaces in a
/// rule match any run of spaces or hyphens. An empty "to" deletes the
/// phrase, which is how filler words like "um" are dropped. Mirrors
/// Sources/DictationCore/Replacements.swift; Voxtype's text.replacements
/// does the same job on Linux.
/// </summary>
public static class Replacements
{
    private static readonly Regex Spaces = new(@"\s+", RegexOptions.Compiled);
    private static readonly Regex SpaceBeforePunctuation = new(@"\s+([,.!?;:])", RegexOptions.Compiled);
    private static readonly Regex LeadingPunctuation = new(@"^[\s,;:.!?]+", RegexOptions.Compiled);
    private static readonly Regex DoubledComma = new(@",\s*,", RegexOptions.Compiled);
    private static readonly Regex CommaAfterStop = new(@"([.!?])[,;:]+", RegexOptions.Compiled);
    private static readonly Regex LowerAfterStop = new(@"([.!?]\s+)(\p{Ll})", RegexOptions.Compiled);

    public static string Apply(string text, IReadOnlyList<Replacement> rules)
    {
        var usable = rules
            .Select(r => new Replacement(Spaces.Replace(r.From, " ").Trim(), r.To.Trim()))
            .Where(r => r.From.Length > 0)
            .GroupBy(r => Key(r.From))
            .Select(g => g.Last())
            // Longest first, so "cloud code" wins over "cloud".
            .OrderByDescending(r => r.From.Length)
            .ToList();
        if (usable.Count == 0 || text.Length == 0) return text;

        var byKey = usable.ToDictionary(r => Key(r.From), r => r.To);
        var alternatives = usable.Select(r => string.Join(@"[\s-]+", r.From.Split(' ').Select(Regex.Escape)));
        var pattern = new Regex(@"(?<![\p{L}\p{N}])(?:" + string.Join("|", alternatives) + @")(?![\p{L}\p{N}])",
                                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        bool deleted = false;
        var result = pattern.Replace(text, m =>
        {
            var to = byKey.TryGetValue(Key(m.Value), out var t) ? t : m.Value;
            if (to.Length == 0) deleted = true;
            return to;
        });
        return deleted ? Tidy(result) : result;
    }

    /// <summary>Lowercased, with spaces and hyphens folded to one space.</summary>
    private static string Key(string phrase) =>
        Regex.Replace(phrase.ToLowerInvariant(), @"[\s-]+", " ").Trim();

    /// <summary>Cleans up after a deleted word: "So, um, yes" reads "So, yes".</summary>
    private static string Tidy(string text)
    {
        var s = Spaces.Replace(text, " ");
        s = SpaceBeforePunctuation.Replace(s, "$1");
        s = DoubledComma.Replace(s, ",");
        s = CommaAfterStop.Replace(s, "$1");
        s = LowerAfterStop.Replace(s, m => m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant());
        s = LeadingPunctuation.Replace(s, "").Trim();
        if (s.Length > 0 && char.IsLower(s[0]) && text.TrimStart().Length > 0 && !char.IsLower(text.TrimStart()[0]))
            s = char.ToUpperInvariant(s[0]) + s[1..];
        return s;
    }
}
