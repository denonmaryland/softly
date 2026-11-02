using System.Windows.Threading;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Softly.Core;

namespace Softly;

/// <summary>
/// Recording lifecycle, the same on every platform:
/// press/hold/double-tap -> record -> transcribe -> paste -> check -> close.
/// Esc or clicking the x cancels and discards at any point.
/// </summary>
public sealed class DictationEngine
{
    public readonly PillModel Pill;
    public RecorderState State { get; private set; } = RecorderState.Idle;
    public Transcriber.Status ModelStatus { get; private set; } = Transcriber.Status.Loading;
    public string Backend => transcriber.Backend;
    public Action OnStatusChange = () => { };

    private readonly GestureController controller = new();
    private readonly AudioRecorder recorder = new();
    private readonly Transcriber transcriber = new();
    private readonly Dispatcher dispatcher;
    private DispatcherTimer? releaseTimer, capTimer;
    /// <summary>Bumped on every start/cancel so stale timers and results are ignored.</summary>
    private int session;

    public DictationEngine(PillModel pill, Dispatcher dispatcher)
    {
        Pill = pill;
        this.dispatcher = dispatcher;
        pill.LevelSource = () => recorder.CurrentRMS;
        pill.OnCancelClick = CancelNow;
        // Input device changed mid-recording: keep what was captured and transcribe it.
        recorder.OnInterrupted = () => dispatcher.BeginInvoke(() => Handle(GestureEvent.Stop));
    }

    public async void LoadModel()
    {
        ModelStatus = Transcriber.Status.Loading;
        OnStatusChange();
        var status = await transcriber.LoadAsync(Settings.ModelPath);
        ModelStatus = status;
        OnStatusChange();
    }

    // Inputs

    /// <summary>Timestamp of the last trigger press on the hook thread, for the latency log.</summary>
    public Func<long>? PressTicks;

    public void Press() => Handle(GestureEvent.Press);
    public void Release() => Handle(GestureEvent.Release);
    public void Toggle() => Handle(GestureEvent.Toggle);

    /// <summary>Another key typed while Right Alt is held: a shortcut, not dictation.</summary>
    public void Chord()
    {
        if (State != RecorderState.Recording || !controller.Held || controller.Locked) return;
        Handle(GestureEvent.Cancel);
    }

    /// <summary>Esc: swallowed only while the pill is up.</summary>
    public bool Escape()
    {
        if (!Pill.Showing) return false;
        CancelNow();
        return true;
    }

    public void CancelNow()
    {
        if (Pill.Previewing)
        {
            session++;
            HidePill(silent: true);
        }
        else if (State == RecorderState.Idle)
        {
            HidePill();
        }
        else
        {
            Handle(GestureEvent.Cancel);
        }
    }

    /// <summary>Test hook: transcribes a WAV file through the loaded model without pasting.</summary>
    public async Task<string> TranscribeFileAsync(string path)
    {
        if (ModelStatus != Transcriber.Status.Ready) return "model not ready: " + ModelStatus;
        float[] samples;
        try
        {
            using var reader = new AudioFileReader(path);
            ISampleProvider provider = reader;
            if (reader.WaveFormat.Channels == 2) provider = provider.ToMono();
            var resampled = new WdlResamplingSampleProvider(provider, 16_000);
            var all = new List<float>();
            var chunk = new float[8192];
            int n;
            while ((n = resampled.Read(chunk, 0, chunk.Length)) > 0) all.AddRange(new ArraySegment<float>(chunk, 0, n));
            samples = all.ToArray();
        }
        catch (Exception e)
        {
            return "read failed: " + e.Message;
        }
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var text = await transcriber.TranscribeAsync(samples);
        return $"{samples.Length / 16_000.0:0.0}s audio in {sw.Elapsed.TotalSeconds:0.00}s via {Backend}: {text ?? "(nothing)"}";
    }

    /// <summary>Silent simulated cycle: never opens the microphone or pastes.</summary>
    public void Preview()
    {
        if (State != RecorderState.Idle) return;
        session++;
        int token = session;
        Pill.BeginSession(preview: true);
        Timing.After(3.2, () => { if (session == token) Pill.SetDisplay(PillModel.Display.Transcribing); });
        Timing.After(4.6, () => { if (session == token) Pill.SetDisplay(PillModel.Display.Complete); });
        Timing.After(5.2, () => { if (session == token) HidePill(silent: true); });
    }

    // Gesture actions

    private void Handle(GestureEvent e)
    {
        foreach (var action in controller.Send(e, PillModel.Now, State))
        {
            switch (action)
            {
                case GestureAction.TimerStart:
                    releaseTimer?.Stop();
                    releaseTimer = Timing.After(GestureController.DoubleTapWindow, () => Handle(GestureEvent.Timeout));
                    break;
                case GestureAction.TimerStop:
                    releaseTimer?.Stop();
                    releaseTimer = null;
                    break;
                case GestureAction.Start: StartRecording(); break;
                case GestureAction.Stop: StopRecording(); break;
                case GestureAction.Cancel: Discard(); break;
            }
        }
    }

    private void StartRecording()
    {
        if (ModelStatus != Transcriber.Status.Ready)
        {
            System.Media.SystemSounds.Beep.Play();
            controller.Send(GestureEvent.Reset, PillModel.Now, RecorderState.Idle);
            OnStatusChange();
            return;
        }
        long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
        try
        {
            recorder.Start();
        }
        catch (Exception)
        {
            System.Media.SystemSounds.Beep.Play();
            controller.Send(GestureEvent.Reset, PillModel.Now, RecorderState.Idle);
            return;
        }
        long t1 = System.Diagnostics.Stopwatch.GetTimestamp();
        session++;
        State = RecorderState.Recording;
        Pill.BeginSession();
        long t2 = System.Diagnostics.Stopwatch.GetTimestamp();
        double Ms(long a, long b) => (b - a) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
        long press = PressTicks?.Invoke() ?? 0;
        App.Log($"start: key->handler {(press > 0 ? Ms(press, t0).ToString("0") : "?")} ms, mic {Ms(t0, t1):0} ms, pill {Ms(t1, t2):0} ms");
        Sounds.PlayOpen();
        MediaPauser.Shared.Pause();
        capTimer?.Stop();
        capTimer = Timing.After(Settings.MaxDuration, () => Handle(GestureEvent.Stop));
    }

    private async void StopRecording()
    {
        if (State != RecorderState.Recording) return;
        capTimer?.Stop();
        var (samples, peak) = recorder.Stop();
        MediaPauser.Shared.Resume();
        State = RecorderState.Transcribing;
        controller.Send(GestureEvent.Reset, PillModel.Now, State);
        Pill.SetDisplay(PillModel.Display.Transcribing);

        // Too short, or silent: Whisper tends to invent text for silence.
        if (samples.Length / 16_000.0 < Settings.MinimumSpeech || peak < Settings.SilenceRMS)
        {
            Finish(null);
            return;
        }
        int token = session;
        var text = await transcriber.TranscribeAsync(samples);
        if (session != token || State != RecorderState.Transcribing) return;
        Finish(text);
    }

    private void Finish(string? text)
    {
        State = RecorderState.Idle;
        controller.Send(GestureEvent.Reset, PillModel.Now, State);
        if (text == null)
        {
            HidePill();
            return;
        }
        Paster.Paste(text, dispatcher);
        // Let the paste land, confirm with a check, then close.
        int token = session;
        Timing.After(0.075, () =>
        {
            if (session != token) return;
            Pill.SetDisplay(PillModel.Display.Complete);
            Timing.After(0.45, () => { if (session == token) HidePill(); });
        });
    }

    private void Discard()
    {
        session++;
        capTimer?.Stop();
        if (State == RecorderState.Recording)
        {
            recorder.Stop();
            MediaPauser.Shared.Resume();
        }
        State = RecorderState.Idle;
        HidePill();
    }

    private void HidePill(bool silent = false)
    {
        if (!Pill.Showing) return;
        bool wasPreview = Pill.Previewing;
        Pill.Hide();
        if (!silent && !wasPreview) Sounds.PlayClose();
    }
}
