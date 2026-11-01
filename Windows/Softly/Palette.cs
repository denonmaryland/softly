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
/// Dark capsule with the Windows accent colour for the backlight, so it
/// follows the system the way the Linux pill follows the Omarchy theme.
/// </summary>
public sealed class Palette
{
    public RGBA Background { get; } = RGBA.FromHex(0x12151C);
    public RGBA Foreground { get; } = RGBA.FromHex(0xE6E8EE);
    public RGBA Accent { get; }
    public RGBA Floor => Background.Darker(1.5);

    public Palette()
    {
        Accent = RGBA.FromHex(0x0078D4);
        try
        {
            var settings = new Windows.UI.ViewManagement.UISettings();
            var c = settings.GetColorValue(Windows.UI.ViewManagement.UIColorType.Accent);
            Accent = new RGBA(c.R / 255.0, c.G / 255.0, c.B / 255.0);
        }
        catch (Exception) { }
    }
}
