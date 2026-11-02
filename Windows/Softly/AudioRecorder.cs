using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Softly.Core;

namespace Softly;

/// <summary>
/// Captures the default input through WASAPI, converts to 16 kHz mono
/// float for Whisper, and publishes a live RMS level for the waveform.
/// Audio stays in memory only.
/// </summary>
public sealed class AudioRecorder
{
    /// <summary>Raised on the capture thread when capture stops on its own (device change).</summary>
    public Action OnInterrupted = () => { };

    private readonly object gate = new();
    private readonly List<float> samples = new();
    private double level, peak;
    private WasapiCapture? capture;
    private BufferedWaveProvider? buffered;
    private ISampleProvider? resampled;
    private readonly float[] chunk = new float[4096];
    private bool running;

    public double CurrentRMS { get { lock (gate) return level; } }

    /// <summary>A copy of the samples captured so far, from <paramref name="start"/> on, for transcribing while recording continues.</summary>
    public float[] Pending(int start)
    {
        lock (gate) return start < samples.Count ? samples.GetRange(start, samples.Count - start).ToArray() : Array.Empty<float>();
    }

    /// <summary>
    /// Touches the capture device and the resampler once so the first
    /// recording does not pay for device activation and JIT. The microphone
    /// is never opened.
    /// </summary>
    public static void WarmUp()
    {
        try
        {
            using var cap = new WasapiCapture();
            var buffer = new BufferedWaveProvider(cap.WaveFormat) { ReadFully = false };
            ISampleProvider provider = buffer.ToSampleProvider();
            if (cap.WaveFormat.Channels == 2) provider = provider.ToMono();
            var resampler = new WdlResamplingSampleProvider(provider, 16_000);
            resampler.Read(new float[64], 0, 64);
        }
        catch (Exception) { }
    }

    public void Start()
    {
        if (running) return;
        var cap = new WasapiCapture();
        var format = cap.WaveFormat;
        var buffer = new BufferedWaveProvider(format)
        {
            BufferDuration = TimeSpan.FromSeconds(10),
            DiscardOnBufferOverflow = true,
            ReadFully = false,
        };
        ISampleProvider provider = buffer.ToSampleProvider();
        if (format.Channels == 2) provider = provider.ToMono();
        else if (format.Channels > 2) provider = new MultiplexingSampleProvider(new[] { provider }, 1);
        resampled = new WdlResamplingSampleProvider(provider, 16_000);
        buffered = buffer;
        lock (gate)
        {
            samples.Clear();
            samples.Capacity = Math.Max(samples.Capacity, 16_000 * 60);
            level = 0;
            peak = 0;
        }
        cap.DataAvailable += OnData;
        cap.RecordingStopped += OnStopped;
        cap.StartRecording();
        capture = cap;
        running = true;
    }

    /// <summary>Stops capture and returns the 16 kHz samples plus the loudest RMS seen.</summary>
    public (float[] Samples, double Peak) Stop()
    {
        if (running)
        {
            running = false;
            var cap = capture;
            capture = null;
            if (cap != null)
            {
                cap.DataAvailable -= OnData;
                cap.RecordingStopped -= OnStopped;
                try { cap.StopRecording(); } catch (Exception) { }
                cap.Dispose();
            }
        }
        lock (gate)
        {
            var result = (samples.ToArray(), peak);
            samples.Clear();
            level = 0;
            peak = 0;
            return result;
        }
    }

    private void OnData(object? sender, WaveInEventArgs e)
    {
        var buffer = buffered;
        var provider = resampled;
        if (buffer == null || provider == null || !running) return;
        buffer.AddSamples(e.Buffer, 0, e.BytesRecorded);
        while (true)
        {
            int n = provider.Read(chunk, 0, chunk.Length);
            if (n <= 0) break;
            double rms = Waveform.RootMeanSquare(new ReadOnlySpan<float>(chunk, 0, n));
            lock (gate)
            {
                level = rms;
                peak = Math.Max(peak, rms);
                samples.AddRange(new ArraySegment<float>(chunk, 0, n));
            }
            if (n < chunk.Length) break;
        }
    }

    private void OnStopped(object? sender, StoppedEventArgs e)
    {
        if (running && e.Exception != null) OnInterrupted();
    }
}
