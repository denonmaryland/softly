using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Fetches a speech model into %LOCALAPPDATA%\Softly\Models, with progress,
/// and verifies its SHA-256 before the engine loads it. Used on first run and
/// when a model that is not on disk yet is picked in Preferences.
/// </summary>
public sealed class ModelDownloader
{
    public enum Phase { Idle, Downloading, Verifying, Failed }

    public Phase State { get; private set; } = Phase.Idle;
    public double Progress { get; private set; }
    public string Error { get; private set; } = "";
    /// <summary>The model being fetched, while downloading, verifying or failed.</summary>
    public SpeechModel? Model { get; private set; }
    public Action OnChange = () => { };
    /// <summary>The file is in place and verified; the engine should switch to it.</summary>
    public Action<SpeechModel> OnComplete = _ => { };
    /// <summary>Bumped on every start and cancel so a replaced download stays quiet.</summary>
    private int generation;

    private readonly Dispatcher dispatcher;
    private CancellationTokenSource? cts;
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    public ModelDownloader(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        Http.DefaultRequestHeaders.UserAgent.ParseAdd($"Softly/{Updater.CurrentVersion} (Windows)");
    }

    /// <summary>Downloads the given model, replacing a download of another one.</summary>
    public async void Start(SpeechModel model)
    {
        if (Model == model && State is Phase.Downloading or Phase.Verifying) return;
        cts?.Cancel();
        cts = new CancellationTokenSource();
        var token = cts.Token;
        int gen = ++generation;
        Model = model;
        Set(gen, Phase.Downloading, 0);
        var part = model.FilePath + ".part";
        try
        {
            Directory.CreateDirectory(Settings.ModelDirectory);
            using var response = await Http.GetAsync(model.Url, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            long total = response.Content.Headers.ContentLength ?? 0, done = 0;
            int lastStep = -1;
            await using (var source = await response.Content.ReadAsStreamAsync(token))
            await using (var file = File.Create(part))
            {
                var buffer = new byte[1 << 16];
                int n;
                while ((n = await source.ReadAsync(buffer, token)) > 0)
                {
                    await file.WriteAsync(buffer.AsMemory(0, n), token);
                    done += n;
                    if (total <= 0) continue;
                    double progress = (double)done / total;
                    int step = (int)(progress * 200);
                    if (step != lastStep) { lastStep = step; Set(gen, Phase.Downloading, progress); }
                }
            }
            Set(gen, Phase.Verifying, 1);
            string hash = await Task.Run(() =>
            {
                using var stream = File.OpenRead(part);
                return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
            }, token);
            if (hash != model.Sha256)
            {
                TryDelete(part);
                Set(gen, Phase.Failed, 0, "The download did not verify. Try again.");
                return;
            }
            File.Move(part, model.FilePath, overwrite: true);
            Set(gen, Phase.Idle, 0, done: model);
        }
        catch (OperationCanceledException)
        {
            TryDelete(part);
        }
        catch (Exception e)
        {
            TryDelete(part);
            Set(gen, Phase.Failed, 0, e.Message);
        }
    }

    public void Cancel()
    {
        cts?.Cancel();
        int gen = ++generation;
        Set(gen, Phase.Idle, 0);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (Exception) { }
    }

    private void Set(int gen, Phase phase, double progress, string error = "", SpeechModel? done = null)
    {
        dispatcher.BeginInvoke(() =>
        {
            if (gen != generation) return;
            State = phase;
            Progress = progress;
            Error = error;
            if (phase == Phase.Idle) Model = null;
            OnChange();
            if (done != null) OnComplete(done);
        });
    }
}
