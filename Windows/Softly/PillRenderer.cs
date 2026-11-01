using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Softly.Core;
using static Softly.Core.MotionMath;

namespace Softly;

/// <summary>
/// Draws the backlit-groove capsule each frame. Layer order, sizes and
/// formulas follow the Mac PillView and the Linux Service.qml so the three
/// look the same.
/// </summary>
public sealed class PillRenderer
{
    private readonly Palette palette;
    private static readonly CultureInfo TimerCulture = CultureInfo.GetCultureInfo("en-US");
    private readonly Typeface timerFace = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);

    public PillRenderer(Palette palette) { this.palette = palette; }

    private static Geometry Capsule(Rect rect)
    {
        var g = new RectangleGeometry(rect, rect.Height / 2, rect.Height / 2);
        g.Freeze();
        return g;
    }

    private static LinearGradientBrush Vertical(Rect r, params (RGBA color, double at)[] stops)
    {
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, r.Top), EndPoint = new Point(0, r.Bottom), MappingMode = BrushMappingMode.Absolute,
        };
        foreach (var (c, at) in stops) brush.GradientStops.Add(new GradientStop(c.Color, at));
        brush.Freeze();
        return brush;
    }

    public void Draw(DrawingContext dc, PillFrame f, double pixelsPerDip)
    {
        double p = f.Presence;
        var size = PillGeometry.PanelSize;
        // The whole surface is composited once, then faded, lifted and scaled.
        dc.PushOpacity(f.Surface);
        var transform = new TransformGroup();
        transform.Children.Add(new TranslateTransform(-size.Width / 2, -size.Height / 2));
        transform.Children.Add(new ScaleTransform(0.96 + 0.04 * p, 0.96 + 0.04 * p));
        transform.Children.Add(new TranslateTransform(size.Width / 2, size.Height / 2 + 4 * (1 - p)));
        dc.PushTransform(transform);
        dc.PushTransform(new TranslateTransform(PillGeometry.Pebble.X, PillGeometry.Pebble.Y));
        DrawPebble(dc);
        DrawGroove(dc, f);
        DrawClock(dc, f, pixelsPerDip);
        dc.Pop();
        dc.Pop();
        dc.Pop();
    }

    // Capsule

    private void DrawPebble(DrawingContext dc)
    {
        double w = PillGeometry.Pebble.Width, h = PillGeometry.Pebble.Height;
        var bg = palette.Background;
        var full = new Rect(0, 0, w, h);

        // Lifted: a soft ambient shadow and a tight contact shadow, drawn as
        // stacked translucent capsules (DrawingContext has no blur).
        for (int i = 0; i < 6; i++)
        {
            double spread = 2 + i * 2.2;
            var rect = new Rect(-spread, 7 - spread * 0.4, w + spread * 2, h + spread * 2 * 0.9);
            dc.DrawGeometry(new RGBA(0, 0, 0, 0.055).Brush, null, Capsule(rect));
        }
        dc.DrawGeometry(new RGBA(0, 0, 0, 0.22).Brush, null, Capsule(new Rect(0.5, 1.5, w - 1, h - 1)));

        dc.DrawGeometry(new RGBA(0, 0, 0, 0.55).Brush, null, Capsule(new Rect(-1, -1, w + 2, h + 2)));
        // Lit chamfer: dark lower lip and lit upper lip peek out around the face.
        dc.DrawGeometry(bg.Darker(1.1).Tint(new RGBA(0, 0, 0, 0.45)).Brush, null, Capsule(full));
        dc.DrawGeometry(bg.Lighter(1.13).Tint(new RGBA(1, 0.98, 0.92, 0.18)).Brush, null, Capsule(new Rect(0, 0, w, h - 1)));
        var face = new Rect(0, 1, w, h - 2);
        dc.DrawGeometry(Vertical(face, (bg.Lighter(1.13), 0), (bg, 0.5), (bg.Darker(1.1), 1)), null, Capsule(face));
    }

    // Groove and waveform

    private void DrawGroove(DrawingContext dc, PillFrame f)
    {
        var g = PillGeometry.Groove;
        var floor = palette.Floor;
        var accent = palette.Accent;
        double c = f.Completion, pr = f.Processing, cp = f.Content;
        dc.PushOpacity(cp);
        dc.PushTransform(new TranslateTransform(g.X, g.Y));
        var full = new Rect(0, 0, g.Width, g.Height);
        // Lower lip catches the backlight; the upper edge falls into shadow.
        dc.DrawGeometry(floor.Tint(accent.Alpha(0.12 + 0.1 * f.Glow)).Brush, null, Capsule(full));
        dc.DrawGeometry(floor.Darker(1.6).Brush, null, Capsule(new Rect(0, 0, g.Width, g.Height - 1)));
        var floorRect = new Rect(0, 1.25, g.Width, g.Height - 2.25);
        dc.DrawGeometry(floor.Brush, null, Capsule(floorRect));

        // Backlight, blooming from the centre as the content arrives.
        dc.PushOpacity(f.Glow * (0.82 + 0.18 * f.Envelope));
        double bloom = 0.55 + 0.45 * cp;
        dc.PushTransform(new ScaleTransform(bloom, 1, g.Width / 2, 0));
        var light = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0), EndPoint = new Point(g.Width, 0), MappingMode = BrushMappingMode.Absolute,
        };
        light.GradientStops.Add(new GradientStop(accent.Alpha(0).Color, 0));
        light.GradientStops.Add(new GradientStop(accent.Alpha(0.08).Color, 0.22));
        light.GradientStops.Add(new GradientStop(accent.Alpha(0.3).Color, 0.5));
        light.GradientStops.Add(new GradientStop(accent.Alpha(0.08).Color, 0.78));
        light.GradientStops.Add(new GradientStop(accent.Alpha(0).Color, 1));
        light.Freeze();
        dc.DrawGeometry(light, null, Capsule(floorRect));
        dc.Pop();
        dc.Pop();

        // Inner shadow under the top edge keeps the glow low in the cut.
        dc.DrawGeometry(Vertical(floorRect, (floor.Darker(1.4).Alpha(0.8), 0), (floor.Alpha(0), 0.45)), null, Capsule(floorRect));

        var shown = f.Shown;
        var ink = palette.Foreground.Brush;
        for (int i = 0; i < Waveform.BarCount; i++)
        {
            double fromCentre = Math.Abs(i - 9) / 9.0;
            double taper = 1 - 0.65 * fromCentre;
            // Centre-out reveal: the outermost bar trails by ~60 ms.
            double reveal = Clamp01((cp - 0.35 * fromCentre) / 0.65);
            double live = shown[i] * taper;
            double busy = 0.15 + 0.32 * (0.5 + 0.5 * Math.Sin(f.Phase * 6 - i * 0.55));
            double activity = (live * (1 - pr) + busy * pr) * (1 - c);
            double home = 8 + i * 4.917;
            // On completion the waveform gathers into the centre dot.
            double x = home + (52.25 - home) * c;
            double height = 2.5 + Math.Min(1, activity) * 13;
            double alpha = (0.95 - 0.25 * pr) * reveal * (1 - Ramp(0.35, 0.9, c));
            if (alpha <= 0.001) continue;
            dc.PushOpacity(alpha);
            dc.DrawRoundedRectangle(ink, null, new Rect(x, (g.Height - height) / 2, 2.5, height), 1.25, 1.25);
            dc.Pop();
        }

        double dotAlpha = Ramp(0.3, 0.85, c);
        if (dotAlpha > 0.001)
        {
            double d = 5 * (0.5 + 0.5 * c);
            dc.PushOpacity(dotAlpha);
            dc.DrawEllipse(ink, null, new Point(g.Width / 2, g.Height / 2), d / 2, d / 2);
            dc.Pop();
        }
        dc.Pop();
        dc.Pop();
    }

    // Timer, glyph, cancel target

    private void DrawClock(DrawingContext dc, PillFrame f, double pixelsPerDip)
    {
        var area = new Rect(112, 0, 41, PillGeometry.Pebble.Height);
        var center = new Point(area.X + area.Width / 2, area.Y + area.Height / 2);
        double scale = f.PressScale;
        double timerMix = (1 - f.Processing) * (1 - f.Completion) * (1 - f.Hover);

        dc.PushOpacity(f.Content);
        dc.PushTransform(new TranslateTransform(center.X, center.Y));
        dc.PushTransform(new ScaleTransform(scale, scale));

        // The timer clears before the glyph shows, so text and icon never overlap.
        if (timerMix > 0.001)
        {
            var text = new FormattedText(f.TimerText, TimerCulture, FlowDirection.LeftToRight,
                timerFace, 11, palette.Foreground.Alpha(0.76).Brush, pixelsPerDip);
            dc.PushOpacity(timerMix * timerMix);
            dc.DrawText(text, new Point(-text.Width / 2, -text.Height / 2));
            dc.Pop();
        }

        double glyphAlpha = (0.76 + 0.24 * f.Hover) * Clamp01(1 - 2.5 * timerMix);
        if (glyphAlpha > 0.001)
        {
            const double unit = 0.8;
            double stroke = f.GlyphStroke;
            dc.PushOpacity(glyphAlpha);
            dc.PushTransform(new TranslateTransform(-7 * unit, -7 * unit));
            foreach (var line in f.GlyphLines)
            {
                if (line.Ink <= 0.001) continue;
                var a = new Point(line.X1 * unit, line.Y1 * unit);
                var b = new Point(line.X2 * unit, line.Y2 * unit);
                dc.PushOpacity(line.Ink);
                if (Math.Sqrt((b.X - a.X) * (b.X - a.X) + (b.Y - a.Y) * (b.Y - a.Y)) < 0.01)
                {
                    dc.DrawEllipse(palette.Foreground.Brush, null, a, stroke / 2, stroke / 2);
                }
                else
                {
                    var pen = new Pen(palette.Foreground.Brush, stroke) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                    pen.Freeze();
                    dc.DrawLine(pen, a, b);
                }
                dc.Pop();
            }
            dc.Pop();
            dc.Pop();
        }
        dc.Pop();
        dc.Pop();
        dc.Pop();
    }
}
