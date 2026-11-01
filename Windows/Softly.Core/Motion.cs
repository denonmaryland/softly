namespace Softly.Core;

/// <summary>CSS-style cubic Bezier timing curve, solved for y given x (time fraction).</summary>
public readonly struct CubicBezier
{
    private readonly double cx, bx, ax, cy, by, ay;

    public CubicBezier(double x1, double y1, double x2, double y2)
    {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx;
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by;
    }

    private double SampleX(double t) => ((ax * t + bx) * t + cx) * t;
    private double SampleY(double t) => ((ay * t + by) * t + cy) * t;
    private double SlopeX(double t) => (3 * ax * t + 2 * bx) * t + cx;

    public double Evaluate(double x)
    {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        double t = x;
        for (int i = 0; i < 8; i++)
        {
            double err = SampleX(t) - x;
            if (Math.Abs(err) < 1e-6) return SampleY(t);
            double d = SlopeX(t);
            if (Math.Abs(d) < 1e-6) break;
            t -= err / d;
        }
        double lo = 0, hi = 1;
        t = x;
        while (hi - lo > 1e-6)
        {
            double v = SampleX(t);
            if (Math.Abs(v - x) < 1e-6) break;
            if (x > v) lo = t; else hi = t;
            t = (lo + hi) / 2;
        }
        return SampleY(t);
    }
}

/// <summary>The curves used by the pill on every platform (Qt easing equivalents).</summary>
public static class Curve
{
    public static readonly CubicBezier OutCubic = new(0.33, 1, 0.68, 1);
    public static readonly CubicBezier InCubic = new(0.32, 0, 0.67, 0);
    public static readonly CubicBezier InOutCubic = new(0.65, 0, 0.35, 1);
    public static readonly CubicBezier InOutQuad = new(0.45, 0, 0.55, 1);
    /// <summary>Exponential ease-out used for the glyph morph.</summary>
    public static readonly CubicBezier Morph = new(0.19, 1, 0.22, 1);
}

/// <summary>
/// A value that eases toward a target. Retargeting starts from the current
/// value, so interruptions never jump.
/// </summary>
public sealed class Tween
{
    public double Target { get; private set; }
    private double from;
    private double start;
    private double delay;
    private double duration;
    private CubicBezier curve = Curve.OutCubic;

    public Tween(double value) { Target = value; from = value; }

    public double ValueAt(double now)
    {
        if (duration <= 0) return Target;
        double x = (now - start - delay) / duration;
        if (x <= 0) return from;
        if (x >= 1) return Target;
        return from + (Target - from) * curve.Evaluate(x);
    }

    public bool IsAnimating(double now) => duration > 0 && now < start + delay + duration;

    public void Animate(double value, double duration, CubicBezier curve, double now, double delay = 0)
    {
        double current = ValueAt(now);
        if (value == Target && !IsAnimating(now)) return;
        from = current;
        Target = value;
        start = now;
        this.delay = delay;
        this.duration = duration;
        this.curve = curve;
    }

    /// <summary>Jump immediately (used while the pill is hidden).</summary>
    public void Snap(double value)
    {
        Target = value; from = value; duration = 0;
    }

    /// <summary>Animate when visible, snap when hidden.</summary>
    public void Set(double value, bool animated, double duration, CubicBezier curve, double now)
    {
        if (animated) Animate(value, duration, curve, now); else Snap(value);
    }
}

public static class MotionMath
{
    public static double Clamp01(double x) => Math.Min(1, Math.Max(0, x));

    /// <summary>Smoothstep between a and b.</summary>
    public static double Ramp(double a, double b, double t)
    {
        double x = Clamp01((t - a) / (b - a));
        return x * x * (3 - 2 * x);
    }
}
