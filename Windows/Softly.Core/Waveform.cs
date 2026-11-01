namespace Softly.Core;

/// <summary>
/// RMS-driven bars, same shaping as the Linux pill. Visualization only;
/// never changes capture gain.
/// </summary>
public sealed class Waveform
{
    public const int BarCount = 19;
    public const double TickInterval = 0.040;

    public double Envelope { get; private set; }
    public double[] Levels { get; private set; } = new double[BarCount];
    public double[] Shown { get; private set; } = new double[BarCount];

    public void Reset()
    {
        Envelope = 0;
        Levels = new double[BarCount];
        Shown = new double[BarCount];
    }

    /// <summary>Every 40 ms: compress and smooth the level, push the newest bar in.</summary>
    public void Tick(double rms, bool transcribing, double jitter)
    {
        double target = Math.Min(1, Math.Sqrt(Math.Max(0, rms)) * 2.2);
        Envelope += (target - Envelope) * (target > Envelope ? 0.5 : 0.2);
        double live = transcribing ? 0 : Envelope * (0.55 + 0.45 * jitter);
        var next = new double[BarCount];
        next[0] = live;
        Array.Copy(Levels, 0, next, 1, BarCount - 1);
        Levels = next;
    }

    /// <summary>Every frame: ease displayed bars toward their levels.</summary>
    public void Frame(double dt)
    {
        double k = 1 - Math.Exp(-dt * 22);
        for (int i = 0; i < BarCount; i++) Shown[i] += (Levels[i] - Shown[i]) * k;
    }

    /// <summary>Root-mean-square of a buffer of samples.</summary>
    public static double RootMeanSquare(ReadOnlySpan<float> samples)
    {
        if (samples.IsEmpty) return 0;
        double sum = 0;
        foreach (var s in samples) sum += (double)s * s;
        return Math.Sqrt(sum / samples.Length);
    }
}
