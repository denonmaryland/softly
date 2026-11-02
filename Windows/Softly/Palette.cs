using System.Windows.Media;

namespace Softly;

/// <summary>
/// Minimal RGBA colour with the Qt helpers the pill uses on every platform
/// (Qt.darker, Qt.lighter, Qt.tint, Qt.alpha).
/// </summary>
public readonly struct RGBA
{
    public readonly double R, G, B, A;

    public RGBA(double r, double g, double b, double a = 1) { R = r; G = g; B = b; A = a; }

    public static RGBA FromHex(uint hex) =>
        new(((hex >> 16) & 0xff) / 255.0, ((hex >> 8) & 0xff) / 255.0, (hex & 0xff) / 255.0);

    public Color Color => System.Windows.Media.Color.FromArgb(
        (byte)Math.Round(Math.Clamp(A, 0, 1) * 255), (byte)Math.Round(Math.Clamp(R, 0, 1) * 255),
        (byte)Math.Round(Math.Clamp(G, 0, 1) * 255), (byte)Math.Round(Math.Clamp(B, 0, 1) * 255));

    public SolidColorBrush Brush
    {
        get { var b = new SolidColorBrush(Color); b.Freeze(); return b; }
    }

    public RGBA Alpha(double value) => new(R, G, B, value);
    /// <summary>HSV value divided by factor (Qt.darker).</summary>
    public RGBA Darker(double factor) => ScaledValue(1 / factor);
    /// <summary>HSV value multiplied by factor (Qt.lighter).</summary>
    public RGBA Lighter(double factor) => ScaledValue(factor);

    /// <summary>overlay composited over this (Qt.tint).</summary>
    public RGBA Tint(RGBA overlay)
    {
        double k = overlay.A;
        return new RGBA(R + (overlay.R - R) * k, G + (overlay.G - G) * k, B + (overlay.B - B) * k, A);
    }

    private RGBA ScaledValue(double factor)
    {
        double maxC = Math.Max(R, Math.Max(G, B));
        if (maxC <= 0)
        {
            double v = Math.Min(1, factor > 1 ? (factor - 1) * 0.1 : 0);
            return new RGBA(v, v, v, A);
        }
        double target = Math.Min(1, maxC * factor);
        double k = target / maxC;
        return new RGBA(R * k, G * k, B * k, A);
    }
}

/// <summary>
/// One pill style: capsule, ink and backlight colours. Light capsules use
/// softer shadows and a shallower groove, as the Linux pill does under a
/// light Omarchy theme. The same table lives in Sources/Softly/Palette.swift
/// and Linux/plugin/Themes.js; keep the three in step.
/// </summary>
public sealed record PillTheme(string Id, string Name, uint Background, uint Foreground, uint? Accent)
{
    public static readonly IReadOnlyList<PillTheme> All = new PillTheme[]
    {
        new("system", "Midnight", 0x12151C, 0xE6E8EE, null),
        new("graphite", "Graphite", 0x1C1D20, 0xEDEDED, 0xD9DCE3),
        new("ember", "Ember", 0x1F1612, 0xF5E7DD, 0xFF7A3D),
        new("forest", "Forest", 0x101A14, 0xDCEBE0, 0x4ADE80),
        new("lagoon", "Lagoon", 0x0D1A20, 0xDCF1F5, 0x2DD4BF),
        new("rose", "Rose", 0x1F1318, 0xF7E4EB, 0xFF5C8A),
        new("violet", "Violet", 0x19112B, 0xEFE6FF, 0xB57BFF),
        new("brass", "Brass", 0x18150E, 0xF2EAD5, 0xF2C14E),
        new("paper", "Paper", 0xF3EFE6, 0x2B2722, 0xE0703A),
        new("frost", "Frost", 0xEDF1F6, 0x1D2633, 0x2F7CF6),
        new("blush", "Blush", 0xF7EAEC, 0x3B242A, 0xE04F78),
    };

    public static PillTheme Named(string id) => All.FirstOrDefault(t => t.Id == id) ?? All[0];
}

/// <summary>
/// The chosen style's colours. Midnight, the default, takes the Windows
/// accent colour for the backlight, so it follows the system the way the
/// Linux pill follows the Omarchy theme.
/// </summary>
public sealed class Palette
{
    public string ThemeId { get; }
    public RGBA Background { get; }
    public RGBA Foreground { get; }
    public RGBA Accent { get; }
    /// <summary>HSL lightness above one half, as Service.qml's lightTheme.</summary>
    public bool IsLight { get; }
    public RGBA Floor => IsLight ? Background.Darker(1.12) : Background.Darker(1.5);

    public Palette(PillTheme theme)
    {
        ThemeId = theme.Id;
        Background = RGBA.FromHex(theme.Background);
        Foreground = RGBA.FromHex(theme.Foreground);
        Accent = theme.Accent is uint hex ? RGBA.FromHex(hex) : SystemAccent();
        double hi = Math.Max(Background.R, Math.Max(Background.G, Background.B));
        double lo = Math.Min(Background.R, Math.Min(Background.G, Background.B));
        IsLight = (hi + lo) / 2 > 0.5;
    }

    private static RGBA SystemAccent()
    {
        try
        {
            var settings = new Windows.UI.ViewManagement.UISettings();
            var c = settings.GetColorValue(Windows.UI.ViewManagement.UIColorType.Accent);
            return new RGBA(c.R / 255.0, c.G / 255.0, c.B / 255.0);
        }
        catch (Exception)
        {
            return RGBA.FromHex(0x0078D4);
        }
    }

    private static Palette? cached;

    /// <summary>The palette for the saved style, rebuilt only when it changes.</summary>
    public static Palette Current
    {
        get
        {
            var theme = PillTheme.Named(Settings.PillTheme);
            if (cached == null || cached.ThemeId != theme.Id) cached = new Palette(theme);
            return cached;
        }
    }
}
