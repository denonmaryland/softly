using System.Text.RegularExpressions;

namespace Softly.Core;

/// <summary>
/// "…and fix the test, submit." Ending a dictation with the word "submit"
/// strips it and asks for Enter after the paste, so a prompt goes to an agent
/// hands-free. Only a final, whole "submit" counts: "resubmit" and a
/// "submit" mid-sentence are left alone. Mirrors Sources/DictationCore/SubmitWord.swift
/// and Linux/plugin/bin/softly-fix.
/// </summary>
public static class SubmitWord
{
    private static readonly Regex Pattern = new(@"^(.*?)[\s,.;:!?-]*(?<![\p{L}\p{N}])submit[\s.!?]*$",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.CultureInvariant);

    public static (string Text, bool Submit) Split(string text)
    {
        var m = Pattern.Match(text);
        return m.Success ? (m.Groups[1].Value.Trim(), true) : (text, false);
    }
}
