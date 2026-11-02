using System.IO;
using System.Text.Json;

namespace Softly;

/// <summary>
/// Recognition settings mirror the Mac app and the Linux Voxtype config
/// (small.en Q5_1, English, four threads, vocabulary prompt). User options
/// persist as JSON in %APPDATA%\Softly\settings.json.
/// </summary>
public static class Settings
{
    public const string AppName = "Softly";
    public const string ModelFileName = "ggml-small.en-q5_1.bin";
    public const string Language = "en";
    public const int Threads = 4;
    /// <summary>Recording cap, 15 minutes.</summary>
    public const double MaxDuration = 900;
    /// <summary>Recordings shorter than this are treated as accidental taps.</summary>
    public const double MinimumSpeech = 0.25;
    /// <summary>Recordings whose loudest moment stays below this RMS are skipped as silence.</summary>
    public const double SilenceRMS = 0.005;
    /// <summary>Empty on first run; each person adds their own names.</summary>
    public static readonly string[] DefaultVocabulary = { };

    public static string SupportDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppName);
    public static string ModelDirectory => Path.Combine(SupportDirectory, "Models");
    public static string ModelPath => Path.Combine(ModelDirectory, ModelFileName);
    private static string SettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppName, "settings.json");

    private sealed class Stored
    {
        public bool SoundsEnabled { get; set; } = true;
        public bool PauseMedia { get; set; } = true;
        public string PillTheme { get; set; } = "system";
        public bool TapToStart { get; set; } = true;
        public List<string> Vocabulary { get; set; } = new(DefaultVocabulary);
    }

    private static readonly object Gate = new();
    private static Stored? cache;

    private static Stored Load()
    {
        lock (Gate)
        {
            if (cache != null) return cache;
            try
            {
                cache = JsonSerializer.Deserialize<Stored>(File.ReadAllText(SettingsPath)) ?? new Stored();
            }
            catch (Exception)
            {
                cache = new Stored();
            }
            return cache;
        }
    }

    private static void Save()
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
                File.WriteAllText(SettingsPath, JsonSerializer.Serialize(Load(), new JsonSerializerOptions { WriteIndented = true }));
            }
            catch (Exception) { }
        }
    }

    public static bool SoundsEnabled
    {
        get => Load().SoundsEnabled;
        set { Load().SoundsEnabled = value; Save(); }
    }

    public static bool PauseMedia
    {
        get => Load().PauseMedia;
        set { Load().PauseMedia = value; Save(); }
    }

    /// <summary>Tap once to start hands-free and again to finish. Off is hold-only.</summary>
    public static bool TapToStart
    {
        get => Load().TapToStart;
        set { Load().TapToStart = value; Save(); }
    }

    /// <summary>The pill's style, an id from PillTheme.All.</summary>
    public static string PillTheme
    {
        get => Load().PillTheme;
        set { Load().PillTheme = value; Save(); }
    }

    public static List<string> Vocabulary
    {
        get => new(Load().Vocabulary);
        set { Load().Vocabulary = new List<string>(value); Save(); }
    }

    /// <summary>The vocabulary as Whisper's initial prompt; empty when there are no words.</summary>
    public static string InitialPrompt
    {
        get
        {
            var words = Load().Vocabulary;
            return words.Count == 0 ? "" : string.Join(", ", words) + ".";
        }
    }
}
