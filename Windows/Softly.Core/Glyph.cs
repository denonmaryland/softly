namespace Softly.Core;

/// <summary>
/// Status glyph: three round-capped lines in a 14-unit box. Unused lines
/// collapse to the centre, so any shape morphs into any other.
/// </summary>
public enum GlyphShape { None, More, Check, Cross }

public static class GlyphShapes
{
    /// <summary>Each line: x1, y1, x2, y2, ink (opacity).</summary>
    public static double[][] Lines(GlyphShape shape) => shape switch
    {
        GlyphShape.None => new[] { new[] { 7.0, 7, 7, 7, 0 }, new[] { 7.0, 7, 7, 7, 0 }, new[] { 7.0, 7, 7, 7, 0 } },
        GlyphShape.More => new[] { new[] { 2.5, 7, 2.5, 7, 1 }, new[] { 7.0, 7, 7, 7, 1 }, new[] { 11.5, 7, 11.5, 7, 1 } },
        GlyphShape.Check => new[] { new[] { 2.5, 7.5, 5.5, 10.5, 1 }, new[] { 5.5, 10.5, 11.5, 3.5, 1 }, new[] { 7.0, 7, 7, 7, 0 } },
        // The outer dots become the diagonals, so dots -> x folds symmetrically.
        GlyphShape.Cross => new[] { new[] { 3.0, 3, 11, 11, 1 }, new[] { 7.0, 7, 7, 7, 0 }, new[] { 11.0, 3, 3, 11, 1 } },
        _ => throw new ArgumentOutOfRangeException(nameof(shape)),
    };

    public static double Stroke(GlyphShape shape) => shape == GlyphShape.More ? 2.5 : 1.5;
}

public readonly record struct GlyphLine(double X1, double Y1, double X2, double Y2, double Ink);

/// <summary>Fifteen tweens (3 lines x 5 values) plus stroke width.</summary>
public sealed class GlyphMotion
{
    public const double Duration = 0.4;
    private readonly Tween[] values;
    private readonly Tween strokeTween;
    public GlyphShape Shape { get; private set; } = GlyphShape.None;

    public GlyphMotion()
    {
        values = GlyphShapes.Lines(GlyphShape.None).SelectMany(l => l).Select(v => new Tween(v)).ToArray();
        strokeTween = new Tween(GlyphShapes.Stroke(GlyphShape.None));
    }

    public void Set(GlyphShape shape, bool animated, double now)
    {
        if (shape == Shape && animated) return;
        Shape = shape;
        int i = 0;
        foreach (var v in GlyphShapes.Lines(shape).SelectMany(l => l))
            values[i++].Set(v, animated, Duration, Curve.Morph, now);
        strokeTween.Set(GlyphShapes.Stroke(shape), animated, Duration, Curve.Morph, now);
    }

    public GlyphLine[] LinesAt(double now)
    {
        var lines = new GlyphLine[3];
        for (int i = 0; i < 3; i++)
        {
            double V(int k) => values[i * 5 + k].ValueAt(now);
            lines[i] = new GlyphLine(V(0), V(1), V(2), V(3), V(4));
        }
        return lines;
    }

    public double StrokeAt(double now) => strokeTween.ValueAt(now);
}
