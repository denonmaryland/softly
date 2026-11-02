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
            // Already running in the tray: launching again (Start menu, desktop
            // shortcut) brings its window forward instead of doing nothing.
            AskRunningCopyToOpen();
            Shutdown();
            return;
        }
        // Dictation has to answer the key at once even when the PC is busy, and
        // launches through a scheduled task or the updater inherit below-normal.
        try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.AboveNormal; } catch (Exception) { }

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
            // Called on the hook thread: decide from the pill's flag, act on the UI thread.
            OnEscape = () =>
            {
                if (!pill.Showing) return false;
                Dispatcher.BeginInvoke(DispatcherPriority.Send, engine.CancelNow);
                return true;
            },
        };
        engine.PressTicks = () => hotkeys.PressTicks;
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
            "toggle" => Run(() => engine.Toggle()),
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

        EnsureStartMenuShortcut();
        bool hooked = hotkeys.Start();
        // Pay the first-press costs now, while nobody is waiting on them.
        Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () =>
        {
            panel.WarmUp();
            AudioRecorder.WarmUp();
        });
        engine.LoadModel();
        Refresh();

        // Something still needs the user: open the window so the status is in front of them.
        if (!hooked || !File.Exists(Settings.ModelPath)) OpenWindow();
    }

    private static Task<string> Run(Action action) { action(); return Task.FromResult("ok"); }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(int processId);

    /// <summary>
    /// The download is a plain folder, so put Softly in the Start menu (and
    /// Start search) the first time it runs, pointing at wherever it lives.
    /// </summary>
    private static void EnsureStartMenuShortcut()
    {
        try
        {
            string exe = Environment.ProcessPath ?? "";
            if (exe.Length == 0) return;
            string link = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Softly.lnk");
            var shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;
            dynamic shell = Activator.CreateInstance(shellType)!;
            if (File.Exists(link) && string.Equals((string)shell.CreateShortcut(link).TargetPath, exe, StringComparison.OrdinalIgnoreCase)) return;
            dynamic shortcut = shell.CreateShortcut(link);
            shortcut.TargetPath = exe;
            shortcut.WorkingDirectory = Path.GetDirectoryName(exe);
            shortcut.IconLocation = exe + ",0";
            shortcut.Description = "Softly dictation";
            shortcut.Save();
        }
        catch (Exception e) { Log("Start menu shortcut: " + e.Message); }
    }

    private static void AskRunningCopyToOpen()
    {
        // The launched copy owns the foreground right now; hand it over so the
        // running copy's window can come to the front.
        AllowSetForegroundWindow(-1);
        try
        {
            using var pipe = new System.IO.Pipes.NamedPipeClientStream(".", "softly-control", System.IO.Pipes.PipeDirection.InOut);
            pipe.Connect(2000);
            using var writer = new StreamWriter(pipe) { AutoFlush = true };
            using var reader = new StreamReader(pipe);
            writer.WriteLine("open");
            reader.ReadLine();
        }
        catch (Exception) { }
    }

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
