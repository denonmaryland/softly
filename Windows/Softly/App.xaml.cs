using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace Softly;

/// <summary>Tray-only app: no main window until asked for one.</summary>
public partial class App : Application
{
    private readonly PillModel pill = new();
    private readonly AppState state = new();
    private DictationEngine? engine;
    private PillWindow? panel;
    private HotkeyMonitor? hotkeys;
    private TrayIcon? tray;
    private MainWindow? mainWindow;
    private Mutex? single;
    private ControlPipe? control;
    private Updater? updater;
    private ModelDownloader? downloader;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        single = new Mutex(true, "Softly.SingleInstance", out bool first);
        if (!first)
        {
            Shutdown();
            return;
        }
        DispatcherUnhandledException += (_, args) =>
        {
            Log("Unhandled: " + args.Exception);
            args.Handled = true;
        };

        engine = new DictationEngine(pill, Dispatcher);
        panel = new PillWindow(pill);
        pill.OnScreenChange = visible =>
        {
            if (visible) panel.Present(); else panel.Dismiss();
        };

        hotkeys = new HotkeyMonitor(Dispatcher)
        {
            OnPress = () => engine.Press(),
            OnRelease = () => engine.Release(),
            OnChord = () => engine.Chord(),
            OnEscape = () => engine.Escape(),
        };
        engine.OnStatusChange = Refresh;
        state.ShowModelFolder = ShowModelFolder;
        state.ReloadModel = () => engine.LoadModel();
        downloader = new ModelDownloader(Dispatcher);
        downloader.OnChange = () =>
        {
            state.DownloadPhase = downloader.State;
            state.DownloadProgress = downloader.Progress;
            state.DownloadError = downloader.Error;
        };
        downloader.OnComplete = () => engine.LoadModel();
        state.DownloadModel = () => downloader.Start();
        state.CancelDownload = () => downloader.Cancel();
        state.PreviewPill = () => engine.Preview();
        updater = new Updater(Dispatcher);
        updater.OnChange = () => Dispatcher.BeginInvoke(() =>
        {
            state.UpdatePhase = updater.State;
            state.UpdateVersion = updater.LatestVersion;
            state.UpdateError = updater.Error;
        });
        state.CheckForUpdates = () => updater.Check();
        state.InstallUpdate = () => updater.Install();
        updater.StartBackgroundChecks();

        tray = new TrayIcon(state) { OpenWindow = OpenWindow, Quit = () => Shutdown() };

        control = new ControlPipe(Dispatcher, command => command switch
        {
            "preview" => Run(() => engine.Preview()),
            "open" => Run(OpenWindow),
            "cancel" => Run(() => engine.CancelNow()),
            "check-update" => Run(() => updater.Check()),
            "download-model" => Run(() => downloader.Start()),
            "download-state" => Task.FromResult($"{downloader.State} {downloader.Progress:0.00} {downloader.Error}"),
            "install-update" => Run(() => updater.Install()),
            "update-state" => Task.FromResult($"{updater.State} {updater.LatestVersion} {updater.Error} current={Updater.CurrentVersion}"),
            "quit" => Run(() => Shutdown()),
            var t when t.StartsWith("paste ") => Run(() => Paster.Paste(t.Substring(6), Dispatcher)),
            var t when t.StartsWith("transcribe ") => engine.TranscribeFileAsync(t.Substring(11).Trim()),
            "state" => Task.FromResult($"model={engine.ModelStatus} backend={engine.Backend} hook={hotkeys.IsRunning} state={engine.State} showing={pill.Showing} ready={state.Ready}"),
            _ => Task.FromResult("unknown command"),
        });
        control.Start();

        bool hooked = hotkeys.Start();
        engine.LoadModel();
        Refresh();

        // Something still needs the user: open the window so the status is in front of them.
        if (!hooked || !File.Exists(Settings.ModelPath)) OpenWindow();
    }

    private static Task<string> Run(Action action) { action(); return Task.FromResult("ok"); }

    private void Refresh()
    {
        if (engine == null) return;
        state.Refresh(engine.ModelStatus, hotkeys?.IsRunning ?? false, engine.Backend);
    }

    private void OpenWindow()
    {
        mainWindow ??= new MainWindow(state);
        mainWindow.Show();
        if (mainWindow.WindowState == WindowState.Minimized) mainWindow.WindowState = WindowState.Normal;
        mainWindow.Activate();
    }

    private void ShowModelFolder()
    {
        Directory.CreateDirectory(Settings.ModelDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", Settings.ModelDirectory) { UseShellExecute = true });
    }

    protected override void OnExit(ExitEventArgs e)
    {
        control?.Dispose();
        hotkeys?.Dispose();
        tray?.Dispose();
        single?.Dispose();
        base.OnExit(e);
    }

    public static void Log(string line)
    {
        try
        {
            Directory.CreateDirectory(Settings.SupportDirectory);
            File.AppendAllText(Path.Combine(Settings.SupportDirectory, "softly.log"), $"{DateTime.Now:s} {line}\n");
        }
        catch (Exception) { }
    }
}
