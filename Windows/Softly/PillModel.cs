using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using Softly.Core;

namespace Softly;

/// <summary>Everything one frame needs, sampled on the UI thread.</summary>
public sealed class PillFrame
{
    public double Presence, Surface, Content, Processing, Completion, Glow, Hover, PressScale;
    public double Envelope, Phase;
    public double[] Shown = Array.Empty<double>();
    public string TimerText = "";
    public GlyphLine[] GlyphLines = Array.Empty<GlyphLine>();
    public double GlyphStroke;
}

/// <summary>Fixed geometry of the pill, in device-independent points.</summary>
public static class PillGeometry
{
    public static readonly Size PanelSize = new(189, 64);
    public static readonly Rect Pebble = new(18, 15.85, 153, 32.3);
    public static readonly Rect Groove = new(5.25, (32.3 - 22) / 2, 107, 22);
    /// <summary>Timer / glyph / cancel target, in panel coordinates.</summary>
    public static readonly Rect ClockRect = new(Pebble.X + 112, Pebble.Y, 41, Pebble.Height);
    /// <summary>Space between the pill and the taskbar / screen edge.</summary>
    public const double BottomMargin = 14;
}

/// <summary>
/// Motion state for the pill, the same behaviours as the Mac and Linux pills.
///
/// Entrance: geometry 260 ms ease-out with 4 pt lift and 0.96->1 scale;
/// surface 160 ms; content 180 ms after 40 ms. Exit: geometry 180 ms ease-in;
/// surface and content fade evenly. State blends snap while hidden so a new
/// session never replays the last ending.
/// </summary>
public sealed class PillModel
{
    public enum Display { Recording, Transcribing, Complete }

    private static readonly Stopwatch Clock = Stopwatch.StartNew();
    public static double Now => Clock.Elapsed.TotalSeconds;

    public bool OnScreen { get; private set; }
    public bool Showing { get; private set; }
    public Display Current { get; private set; } = Display.Recording;
    public bool Previewing { get; private set; }

    public readonly Tween Presence = new(0), Surface = new(0), Content = new(0), Processing = new(0),
        Completion = new(0), Glow = new(1), Hover = new(0), PressScale = new(1);
    public readonly GlyphMotion Glyph = new();

    private readonly Waveform waveform = new();
    private double phase;
    private int elapsed;
    private double startedAt;
    private double? lastFrame;
    private bool hovering;
    private readonly DispatcherTimer levelTimer;
    private int hideCheck;
    private readonly Random random = new();

    /// <summary>Live microphone RMS, provided by the engine.</summary>
    public Func<double> LevelSource = () => 0;
    public Action OnCancelClick = () => { };
    public Action<bool> OnScreenChange = _ => { };
    /// <summary>Pointer location in pill coordinates, or null when outside the panel.</summary>
    public Func<Point?> PointerLocation = () => null;

    public PillModel()
    {
        levelTimer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromSeconds(Waveform.TickInterval) };
        levelTimer.Tick += (_, _) => TickLevels();
    }

    public string TimerText => $"{elapsed / 60}:{elapsed % 60:00}";
    private bool Animated => OnScreen;

    // Session

    public void BeginSession(bool preview = false)
    {
        Previewing = preview;
        SetDisplay(Display.Recording);
        waveform.Reset();
        startedAt = Now;
        elapsed = 0;
        Show();
    }

    public void SetDisplay(Display next)
    {
        Current = next;
        double now = Now;
        Processing.Set(next == Display.Transcribing ? 1 : 0, Animated, 0.18, Curve.InOutCubic, now);
        Completion.Set(next == Display.Complete ? 1 : 0, Animated, 0.18, Curve.InOutCubic, now);
        double light = next == Display.Transcribing ? 0 : (next == Display.Complete ? 0.55 : 1);
        Glow.Set(light, Animated, 0.22, Curve.InOutCubic, now);
        UpdateHover(now);
    }

    public void Show()
    {
        double now = Now;
        Showing = true;
        hideCheck++;
        if (!OnScreen)
        {
            OnScreen = true;
            OnScreenChange(true);
        }
        Presence.Animate(1, 0.26, Curve.OutCubic, now);
        Surface.Animate(1, 0.16, Curve.OutCubic, now);
        Content.Animate(1, 0.18, Curve.OutCubic, now, delay: 0.04);
        levelTimer.Start();
    }

    public void Hide()
    {
        if (!Showing) return;
        double now = Now;
        Showing = false;
        Previewing = false;
        Presence.Animate(0, 0.18, Curve.InCubic, now);
        Surface.Animate(0, 0.18, Curve.InOutQuad, now);
        Content.Animate(0, 0.11, Curve.InOutQuad, now);
        levelTimer.Stop();
        hideCheck++;
        int token = hideCheck;
        Timing.After(0.25, () =>
        {
            if (token != hideCheck || Showing) return;
            OnScreen = false;
            OnScreenChange(false);
        });
    }

    // Clock

    private void TickLevels()
    {
        double rms = LevelSource();
        if (Previewing)
        {
            // Speech-like fake level so the look can be checked without the mic.
            rms = 0.004 + 0.09 * Math.Pow(Math.Abs(Math.Sin(phase * 3.1) * Math.Sin(phase * 0.7 + 0.6)), 1.2) * random.NextDouble();
        }
        waveform.Tick(rms, Current == Display.Transcribing, random.NextDouble());
        if (Current == Display.Recording) elapsed = (int)(Now - startedAt);
    }

    /// <summary>Called once per displayed frame: advances the clock and samples every animated value.</summary>
    public PillFrame NextFrame()
    {
        double now = Now;
        double dt = Math.Min(0.1, Math.Max(0, now - (lastFrame ?? now)));
        lastFrame = now;
        phase += dt;
        waveform.Frame(dt);
        UpdateHover(now);
        return new PillFrame
        {
            Presence = Presence.ValueAt(now), Surface = Surface.ValueAt(now),
            Content = Content.ValueAt(now), Processing = Processing.ValueAt(now),
            Completion = Completion.ValueAt(now), Glow = Glow.ValueAt(now),
            Hover = Hover.ValueAt(now), PressScale = PressScale.ValueAt(now),
            Envelope = waveform.Envelope, Phase = phase, Shown = waveform.Shown,
            TimerText = TimerText, GlyphLines = Glyph.LinesAt(now), GlyphStroke = Glyph.StrokeAt(now),
        };
    }

    // Pointer

    private void UpdateHover(double now)
    {
        var p = PointerLocation();
        bool inside = p.HasValue && PillGeometry.ClockRect.Contains(p.Value);
        hovering = inside && Showing && Content.ValueAt(now) > 0.9;
        double target = hovering && Current != Display.Complete ? 1 : 0;
        if (target != Hover.Target) Hover.Set(target, Animated, 0.14, Curve.InOutCubic, now);
        var shape = Current == Display.Complete ? GlyphShape.Check
            : hovering ? GlyphShape.Cross
            : Current == Display.Transcribing ? GlyphShape.More : GlyphShape.None;
        if (shape != Glyph.Shape || !Animated) Glyph.Set(shape, Animated, now);
    }

    public void PointerDown(Point point)
    {
        if (!PillGeometry.ClockRect.Contains(point)) return;
        PressScale.Animate(0.97, 0.14, Curve.OutCubic, Now);
    }

    public void PointerUp(Point point, Point startedAtPoint)
    {
        PressScale.Animate(1, 0.14, Curve.OutCubic, Now);
        var rect = PillGeometry.ClockRect;
        if (rect.Contains(point) && rect.Contains(startedAtPoint) && Showing && Content.ValueAt(Now) > 0.9)
            OnCancelClick();
    }
}

/// <summary>One-shot delays on the UI thread.</summary>
public static class Timing
{
    public static DispatcherTimer After(double seconds, Action body)
    {
        var timer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) => { timer.Stop(); body(); };
        timer.Start();
        return timer;
    }
}
