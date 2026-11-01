using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Checks GitHub Releases for a newer Softly and installs it over this copy.
/// The release asset is the self-contained publish folder zipped by CI.
/// </summary>
public sealed class Updater
{
    public enum Phase { Idle, Checking, UpToDate, Available, Downloading, Failed }

    public const string Repo = "denonmaryland/softly";
    public const string AssetName = "Softly-windows.zip";
    public static string CurrentVersion =>
        typeof(Updater).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "0";

    public Phase State { get; private set; } = Phase.Idle;
    public string LatestVersion { get; private set; } = "";
    public string Error { get; private set; } = "";
    public Action OnChange = () => { };

    private readonly Dispatcher dispatcher;
    private string? assetUrl;
    private DispatcherTimer? periodic;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    public Updater(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        Http.DefaultRequestHeaders.UserAgent.ParseAdd($"Softly/{CurrentVersion} (Windows)");
        Http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    /// <summary>Quiet check shortly after launch and every six hours.</summary>
    public void StartBackgroundChecks()
    {
        Timing.After(5, () => Check(quiet: true));
        periodic = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromHours(6) };
        periodic.Tick += (_, _) => Check(quiet: true);
        periodic.Start();
    }

    private void Set(Phase phase, string latest = "", string error = "")
    {
        State = phase;
        LatestVersion = latest;
        Error = error;
        OnChange();
    }

    public async void Check(bool quiet = false)
    {
        if (State is Phase.Checking or Phase.Downloading) return;
        if (State == Phase.Available && quiet) return;
        Set(Phase.Checking);
        try
        {
            var (version, url) = await FetchLatestAsync();
            if (IsNewer(version, CurrentVersion))
            {
                assetUrl = url;
                Set(Phase.Available, version);
            }
            else Set(quiet ? Phase.Idle : Phase.UpToDate);
        }
        catch (Exception e)
        {
            Set(quiet ? Phase.Idle : Phase.Failed, "", e.Message);
        }
    }

    /// <summary>Downloads and unpacks the zip, then hands over to a script that swaps the files once this process exits.</summary>
    public async void Install()
    {
        if (assetUrl == null || State == Phase.Downloading) return;
        Set(Phase.Downloading, LatestVersion);
        try
        {
            var work = Path.Combine(Path.GetTempPath(), "softly-update");
            if (Directory.Exists(work)) Directory.Delete(work, true);
            Directory.CreateDirectory(work);
            var zip = Path.Combine(work, AssetName);
            await using (var stream = await Http.GetStreamAsync(assetUrl))
            await using (var file = File.Create(zip))
                await stream.CopyToAsync(file);
            var fresh = Path.Combine(work, "new");
            ZipFile.ExtractToDirectory(zip, fresh);
            if (!File.Exists(Path.Combine(fresh, "Softly.exe"))) throw new InvalidDataException("The download did not contain Softly.exe");

            var install = AppContext.BaseDirectory.TrimEnd('\\');
            var script = Path.Combine(work, "swap.cmd");
            int pid = Environment.ProcessId;
            File.WriteAllText(script, $"""
                @echo off
                :wait
                tasklist /fi "PID eq {pid}" 2>nul | find "{pid}" >nul && (timeout /t 1 /nobreak >nul & goto wait)
                robocopy "{fresh}" "{install}" /E /IS /IT /NFL /NDL /NJH /NJS >nul
                start "" "{install}\Softly.exe"
                """);
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"") { UseShellExecute = false, CreateNoWindow = true });
            dispatcher.BeginInvoke(() => Application.Current.Shutdown());
        }
        catch (Exception e)
        {
            Set(Phase.Failed, LatestVersion, e.Message);
        }
    }

    private static async Task<(string Version, string Url)> FetchLatestAsync()
    {
        using var doc = JsonDocument.Parse(await Http.GetStringAsync($"https://api.github.com/repos/{Repo}/releases/latest"));
        var root = doc.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var version = tag.StartsWith('v') ? tag[1..] : tag;
        foreach (var asset in root.GetProperty("assets").EnumerateArray())
            if (asset.GetProperty("name").GetString() == AssetName)
                return (version, asset.GetProperty("browser_download_url").GetString() ?? throw new InvalidDataException("no url"));
        throw new InvalidDataException("No Windows build in the latest release");
    }

    /// <summary>Numeric dotted comparison: 0.2.0 is newer than 0.1.10.</summary>
    public static bool IsNewer(string a, string b)
    {
        static int[] Parts(string s) => s.Split('.').Select(p => int.TryParse(new string(p.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0).ToArray();
        var pa = Parts(a); var pb = Parts(b);
        for (int i = 0; i < Math.Max(pa.Length, pb.Length); i++)
        {
            int x = i < pa.Length ? pa[i] : 0, y = i < pb.Length ? pb[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }
}
