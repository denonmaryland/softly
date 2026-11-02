namespace Softly.Core;

/// <summary>
/// The languages Softly offers, as Whisper language codes. "auto" lets the
/// model detect it. Same list as Sources/DictationCore/Languages.swift and
/// the Linux helper (control.py LANGUAGES).
/// </summary>
public static class Languages
{
    public static readonly (string Code, string Name)[] All =
    {
        ("en", "English"), ("auto", "Detect automatically"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"),
    };

    public static string Name(string code) => All.FirstOrDefault(l => l.Code == code).Name ?? code;

    /// <summary>English-only model files are smaller and better at English; any other choice needs the multilingual file.</summary>
    public static bool NeedsMultilingual(string code) => code != "en";
}
