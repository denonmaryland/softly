using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Softly;

/// <summary>
/// What the window and the tray menu show: model status and the user
/// settings. The app refreshes it whenever something changes.
/// </summary>
public sealed class AppState : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private Transcriber.Status modelStatus = Transcriber.Status.Loading;
    private bool hotkeyRunning;
    private string backend = "";
    private bool soundsEnabled = Settings.SoundsEnabled;
    private bool pauseMedia = Settings.PauseMedia;
    private List<string> vocabulary = Settings.Vocabulary;
    private Updater.Phase updatePhase = Updater.Phase.Idle;
    private string updateVersion = "", updateError = "";

    public Transcriber.Status ModelStatus { get => modelStatus; set => Set(ref modelStatus, value, nameof(Ready), nameof(StatusLine), nameof(ModelText)); }
    public bool HotkeyRunning { get => hotkeyRunning; set => Set(ref hotkeyRunning, value, nameof(Ready), nameof(StatusLine)); }
    public string Backend { get => backend; set => Set(ref backend, value, nameof(ModelText)); }

    public bool SoundsEnabled
    {
        get => soundsEnabled;
        set { if (Set(ref soundsEnabled, value)) Settings.SoundsEnabled = value; }
    }

    public bool PauseMedia
    {
        get => pauseMedia;
        set { if (Set(ref pauseMedia, value)) Settings.PauseMedia = value; }
    }

    public List<string> Vocabulary
    {
        get => vocabulary;
        set { if (Set(ref vocabulary, value, nameof(PromptText))) Settings.Vocabulary = value; }
    }

    public Updater.Phase UpdatePhase { get => updatePhase; set => Set(ref updatePhase, value, nameof(UpdateText)); }
    public string UpdateVersion { get => updateVersion; set => Set(ref updateVersion, value, nameof(UpdateText)); }
    public string UpdateError { get => updateError; set => Set(ref updateError, value, nameof(UpdateText)); }

    /// <summary>Wired by the app; views only call them.</summary>
    public Action ShowModelFolder = () => { };
    public Action ReloadModel = () => { };
    public Action PreviewPill = () => { };
    public Action CheckForUpdates = () => { };
    public Action InstallUpdate = () => { };

    public string UpdateText => updatePhase switch
    {
        Updater.Phase.Checking => "Checking…",
        Updater.Phase.UpToDate => "Up to date",
        Updater.Phase.Available => "Update to " + updateVersion,
        Updater.Phase.Downloading => "Downloading…",
        Updater.Phase.Failed => "Try again",
        _ => "Check for updates",
    };

    public bool Ready => modelStatus == Transcriber.Status.Ready && hotkeyRunning;

    /// <summary>One line for the tray and the Home status; same wording in both places.</summary>
    public string StatusLine => modelStatus switch
    {
        Transcriber.Status.Loading => "Loading speech model…",
        Transcriber.Status.MissingModel => "Model missing: " + Settings.ModelFileName,
        Transcriber.Status.Failed => "Model failed to load",
        _ => hotkeyRunning ? "Ready: hold Right Alt to dictate" : "Keyboard hook could not start",
    };

    public string ModelText => modelStatus switch
    {
        Transcriber.Status.Ready => "Loaded on this PC" + (backend.Length > 0 ? " · " + backend : ""),
        Transcriber.Status.Loading => "Loading…",
        Transcriber.Status.MissingModel => "Model missing",
        _ => "Failed to load",
    };

    public string PromptText => Settings.InitialPrompt.Length > 0 ? "Sent to the model as: “" + Settings.InitialPrompt + "”" : "No words yet. Whisper uses its defaults.";

    private bool Set<T>(ref T field, T value, params string[] also)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        return Raise(also);
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null, params string[] also)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        Raise(also);
        return true;
    }

    private bool Raise(string[] names)
    {
        foreach (var n in names) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
        return true;
    }

    public void Refresh(Transcriber.Status status, bool hotkey, string backendName)
    {
        ModelStatus = status;
        HotkeyRunning = hotkey;
        Backend = backendName;
    }
}
