/// The languages Softly offers, as Whisper language codes. "auto" lets the
/// model detect it. Same list as Windows/Softly.Core/Languages.cs and the
/// Linux helper (control.py LANGUAGES).
public enum Languages {
    public static let all: [(code: String, name: String)] = [
        ("en", "English"), ("auto", "Detect automatically"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"),
    ]

    public static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// English-only model files are smaller and better at English; any other
    /// choice needs the multilingual file.
    public static func needsMultilingual(_ code: String) -> Bool { code != "en" }
}
