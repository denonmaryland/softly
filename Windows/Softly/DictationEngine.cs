using System.Windows.Threading;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Softly.Core;

namespace Softly;

/// <summary>
/// Recording lifecycle, the same on every platform:
/// tap/hold -> record -> transcribe -> paste -> check -> close.
/// Esc or clicking the x cancels and discards at any point.
/// </summary>
public sealed class DictationEngine
{
    public readonly PillModel Pill;
    public RecorderState State { get; private set; } = RecorderState.Idle;
    public Transcriber.Status ModelStatus { get; private set; } = Transcriber.Status.Loading;
    public string Backend => transcriber.Backend;
    public Action OnStatusChange = () => { };
    /// <summary>Called with each pasted transcript, for the window's Recent list.</summary>
    public Action<string> OnDictated = _ => { };
    /// <summary>
    /// The last few dictations, newest first. Held in memory only, like the
    /// Linux popover's list, so nothing said is ever written to disk.
    /// </summary>
    public IReadOnlyList<string> Recent => recent;
    private List<string> recent = new();

    private readonly GestureController controller = new();
    private readonly AudioRecorder recorder = new();
    private readonly Transcriber whisper = new();
    private readonly ParakeetTranscriber parakeet = new();
    /// <summary>The engine the current speech model uses; set by LoadModel.</summary>
    private ISpeechBackend transcriber;
    private readonly Dispatcher dispatcher;
    private DispatcherTimer? capTimer;
    /// <summary>
    /// Transcribing while you talk: pieces of a long recording, in order;
    /// <c>committed</c> samples have been handed out.
    /// </summary>
    private readonly List<Task<string?>> pieces = new();
    private int committed;
    private DispatcherTimer? chunkTimer;
    /// <summary>Bumped on every start/cancel so stale timers and results are ignored.</summary>
    private int session;

    public DictationEngine(PillModel pill, Dispatcher dispatcher)
    {
        Pill = pill;
        this.dispatcher = dispatcher;
        transcriber = SpeechModel.Current.Engine == SpeechEngine.Parakeet ? parakeet : whisper;
        pill.LevelSource = () => recorder.CurrentRMS;
        pill.OnCancelClick = CancelNow;
        // Input device changed mid-recording: keep what was captured and transcribe it.
        recorder.OnInterrupted = () => dispatcher.BeginInvoke(() => Handle(GestureEvent.Stop));
    }

    public async void LoadModel()
    {
        ModelStatus = Transcriber.Status.Loading;
        OnStatusChange();
        ISpeechBackend next = SpeechModel.Current.Engine == SpeechEngine.Parakeet ? parakeet : whisper;
        if (next != transcriber) transcriber.Unload();
        transcriber = next;
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

    /// <summary>
    /// Test hook: plays a WAV file through transcribe-while-talking as if it
    /// were being recorded, and compares the wait after "stop" with a single
    /// pass over the whole file. Nothing is pasted.
    /// </summary>
    public async Task<string> TranscribeAheadFileAsync(string path)
    {
        if (ModelStatus != Transcriber.Status.Ready) return "model not ready: " + ModelStatus;
        float[] samples;
        try { samples = ReadWav(path); } catch (Exception e) { return "read failed: " + e.Message; }
        var done = new List<string?>();
        int start = 0;
        for (int end = Chunking.SampleRate; end <= samples.Length; end += Chunking.SampleRate)
        {
            if (Chunking.Cut(samples[start..end]) is int cut)
            {
                done.Add(await transcriber.TranscribeAsync(samples[start..(start + cut)], Chunking.Join(done) ?? ""));
                start += cut;
            }
        }
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var last = await transcriber.TranscribeAsync(samples[start..], Chunking.Join(done) ?? "");
        double after = sw.Elapsed.TotalSeconds;
        sw.Restart();
        var whole = await transcriber.TranscribeAsync(samples);
        double single = sw.Elapsed.TotalSeconds;
        return $"{samples.Length / 16_000.0:0.0}s audio, {done.Count + 1} pieces; wait after stop {after:0.00}s vs single pass {single:0.00}s || " +
               $"PIECES: {Chunking.Join(done.Append(last))} || SINGLE: {whole}";
    }

    private static float[] ReadWav(string path)
    {
        using var reader = new AudioFileReader(path);
        ISampleProvider provider = reader;
        if (reader.WaveFormat.Channels == 2) provider = provider.ToMono();
        var resampled = new WdlResamplingSampleProvider(provider, 16_000);
        var all = new List<float>();
        var chunk = new float[8192];
        int n;
        while ((n = resampled.Read(chunk, 0, chunk.Length)) > 0) all.AddRange(new ArraySegment<float>(chunk, 0, n));
        return all.ToArray();
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
        var fixedText = text == null ? null : Replacements.Apply(text, Settings.Replacements);
        return $"{samples.Length / 16_000.0:0.0}s audio in {sw.Elapsed.TotalSeconds:0.00}s via {Backend}: {text ?? "(nothing)"} => {fixedText ?? "(nothing)"}";
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
        controller.TapToStart = Settings.TapToStart;
        foreach (var action in controller.Send(e, PillModel.Now, State))
        {
            switch (action)
            {
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
        pieces.Clear();
        committed = 0;
        chunkTimer?.Stop();
        chunkTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromSeconds(1) };
        chunkTimer.Tick += (_, _) => TranscribeAhead();
        chunkTimer.Start();
    }

    /// <summary>
    /// Once a second while recording: when enough audio has piled up and
    /// there is a pause to cut at, transcribe up to it in the background.
    /// </summary>
    private void TranscribeAhead()
    {
        if (State != RecorderState.Recording || pieces.Any(p => !p.IsCompleted)) return;
        var pending = recorder.Pending(committed);
        if (Chunking.Cut(pending) is not int cut) return;
        committed += cut;
        pieces.Add(transcriber.TranscribeAsync(pending[..cut], Chunking.Join(pieces.Select(p => p.Result)) ?? ""));
    }

    private async void StopRecording()
    {
        if (State != RecorderState.Recording) return;
        capTimer?.Stop();
        chunkTimer?.Stop();
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
        string? text;
        if (committed == 0)
        {
            text = await transcriber.TranscribeAsync(samples);
        }
        else
        {
            // Earlier pieces were transcribed while recording; only the rest is left.
            var done = await Task.WhenAll(pieces);
            var tail = samples[Math.Min(committed, samples.Length)..];
            bool speech = tail.Length / 16_000.0 >= Settings.MinimumSpeech && Chunking.Loudest(tail) >= Settings.SilenceRMS;
            var last = speech ? await transcriber.TranscribeAsync(tail, Chunking.Join(done) ?? "") : null;
            text = Chunking.Join(done.Append(last));
        }
        if (session != token || State != RecorderState.Transcribing) return;
        Finish(text);
    }

    private void Finish(string? transcript)
    {
        State = RecorderState.Idle;
        controller.Send(GestureEvent.Reset, PillModel.Now, State);
        // "Heard this, type that" fixes, then a final spoken "submit".
        string? text = transcript == null ? null : Replacements.Apply(transcript, Settings.Replacements);
        bool submit = false;
        if (text != null && Settings.SubmitWord) (text, submit) = SubmitWord.Split(text);
        // A transcript that was all filler is dropped, unless it said "submit".
        if (text == null || (text.Length == 0 && !submit))
        {
            HidePill();
            return;
        }
        if (text.Length > 0)
        {
            recent = new[] { text }.Concat(recent.Where(r => r != text).Take(4)).ToList();
            OnDictated(text);
        }
        Paster.Paste(text, dispatcher, submit);
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
        chunkTimer?.Stop();
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
