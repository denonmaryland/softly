using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Fetches the speech model into %LOCALAPPDATA%\Softly\Models on first run,
/// with progress, and verifies it before the engine loads it. The same file
/// the Mac and Linux builds use.
/// </summary>
public sealed class ModelDownloader
{
    public enum Phase { Idle, Downloading, Verifying, Failed }

    public const string Url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin";
    public const string Sha1 = "20f54878d608f94e4a8ee3ae56016571d47cba34";
    public const int SizeMB = 181;

    public Phase State { get; private set; } = Phase.Idle;
    public double Progress { get; private set; }
    public string Error { get; private set; } = "";
    public Action OnChange = () => { };
    /// <summary>The file is in place and verified; the engine should load it.</summary>
    public Action OnComplete = () => { };

    private readonly Dispatcher dispatcher;
    private CancellationTokenSource? cts;
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    public ModelDownloader(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        Http.DefaultRequestHeaders.UserAgent.ParseAdd($"Softly/{Updater.CurrentVersion} (Windows)");
    }

    public async void Start()
    {
        if (State is Phase.Downloading or Phase.Verifying) return;
        cts = new CancellationTokenSource();
        var token = cts.Token;
        Set(Phase.Downloading, 0);
        var part = Settings.ModelPath + ".part";
        try
        {
            Directory.CreateDirectory(Settings.ModelDirectory);
            using var response = await Http.GetAsync(Url, HttpCompletionOption.ResponseHeadersRead, token);
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
                    if (step != lastStep) { lastStep = step; Set(Phase.Downloading, progress); }
                }
            }
            Set(Phase.Verifying, 1);
            string hash = await Task.Run(() =>
            {
                using var stream = File.OpenRead(part);
                return Convert.ToHexString(SHA1.HashData(stream)).ToLowerInvariant();
            }, token);
            if (hash != Sha1)
            {
                TryDelete(part);
                Set(Phase.Failed, 0, "The download did not verify. Try again.");
                return;
            }
            File.Move(part, Settings.ModelPath, overwrite: true);
            Set(Phase.Idle, 0);
            _ = dispatcher.BeginInvoke(() => OnComplete());
        }
        catch (OperationCanceledException)
        {
            TryDelete(part);
            Set(Phase.Idle, 0);
        }
        catch (Exception e)
        {
            TryDelete(part);
            Set(Phase.Failed, 0, e.Message);
        }
    }

    public void Cancel() => cts?.Cancel();

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (Exception) { }
    }

    private void Set(Phase phase, double progress, string error = "")
    {
        dispatcher.BeginInvoke(() =>
        {
            State = phase;
            Progress = progress;
            Error = error;
            OnChange();
        });
    }
}
