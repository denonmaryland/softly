using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Softly.Core;

namespace Softly;

/// <summary>
/// Home, Speech, Words, Shortcut, Look and About behind a sidebar: the same
/// window the Mac app has (Paper "A · Gallery", page 0.3 · Redesign), in WPF.
/// </summary>
public partial class MainWindow : Window
{
    private readonly AppState state;
    private static readonly Brush Ink = Hex(0x0B0B0C), Muted = Hex(0x6B6F76), Faint = Hex(0x9A9EA5),
        Hairline = Hex(0xE6E7EA), Cobalt = Hex(0x1F4FFF), CobaltWash = Hex(0xEEF2FF), Green = Hex(0x1F9D55), Amber = Hex(0xD97706);
    /// <summary>Set while Bind updates controls, so their change events don't write back.</summary>
    private bool binding;

    public MainWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        state.PropertyChanged += OnStateChanged;
        Closing += (_, e) =>
        {
            // Closing hides; the tray keeps the app alive.
            e.Cancel = true;
            // A capture left running would quietly take the next key pressed elsewhere.
            if (state.CapturingHotkey) state.CancelCapture();
            Hide();
        };
        BuildModelRows();
        BuildThemeSwatches();
        // The first entry stands in while English or Detect is picked.
        LanguageBox.Items.Add(new ComboBoxItem { Content = "15 more languages", Tag = "", Foreground = Muted });
        foreach (var (code, name) in Languages.All.Where(l => l.Code is not ("en" or "auto")))
            LanguageBox.Items.Add(new ComboBoxItem { Content = name, Tag = code });
        Bind();
    }

    private static SolidColorBrush Hex(uint rgb) =>
        new(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));

    private void OnStateChanged(object? sender, PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(Bind);

    private void Bind()
    {
        binding = true;
        string key = state.Hotkey.Name;
        bool ready = state.Ready;
        bool modelMissing = state.ModelStatus == Transcriber.Status.MissingModel;
        bool starting = state.ModelStatus == Transcriber.Status.Loading && state.HotkeyRunning;

        // Sidebar
        SideDot.Fill = ready ? Green : Amber;
        SideStatus.Text = ready ? "Ready" : starting ? "Starting" : "Needs attention";
        SideHint.Text = ready ? "Tap " + key + " to dictate" : state.StatusLine;

        // Home
        HomeTitle.Text = ready ? "Ready" : starting ? "Starting" : "Almost ready";
        HomeSub.Text = ready ? "Tap " + key + " anywhere, talk, and tap again. The words land where your cursor is." : state.StatusLine;
        bool setup = !ready && !starting && (modelMissing || !state.HotkeyRunning || state.ModelStatus == Transcriber.Status.Failed);
        HomeSetup.Visibility = setup ? Visibility.Visible : Visibility.Collapsed;
        TrySection.Style = (Style)FindResource(setup ? "Section" : "FirstSection");
        SetupTitle.Text = state.HotkeyRunning ? "Speech model" : "Keyboard";
        SetupSub.Text = state.HotkeyRunning ? state.ModelText : "The keyboard hook could not start; restart Softly";
        string modelAction = state.ModelActionText;
        HomeModelAction.Content = modelAction;
        HomeModelAction.Visibility = modelAction.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        ModelNote.Text = state.DownloadError;
        ModelNote.Visibility = state.DownloadPhase == ModelDownloader.Phase.Failed && state.DownloadError.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        HomeKey.Text = key;
        HomeGesture.Text = state.TapToStart ? "tap or hold" : "hold";
        PracticeHint.Text = "Click here, tap " + key + " and say something…";
        RecentList.ItemsSource = state.Recent.Select(r => new RecentRow(r.Text, r.At)).ToList();
        RecentEmpty.Visibility = state.Recent.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Speech
        BindModelRows();
        LangEnglish.Tag = state.Language == "en" ? "on" : null;
        LangDetect.Tag = state.Language == "auto" ? "on" : null;
        LanguageBox.SelectedItem = LanguageBox.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == state.Language)
                                   ?? LanguageBox.Items[0];
        LanguageDetail.Text = state.SpeechModel == SpeechModel.Parakeet.Id ? "Parakeet detects the language itself." : "What you speak.";
        SubmitSwitch.IsChecked = state.SubmitWord;

        // Words
        WordList.ItemsSource = state.Vocabulary.ToList();
        RuleList.ItemsSource = state.Replacements.Select(r => new RuleRow(r)).ToList();

        // Shortcut
        ShortcutKey.Text = key;
        ShortcutCap.Visibility = state.CapturingHotkey ? Visibility.Collapsed : Visibility.Visible;
        ShortcutWaiting.Visibility = state.CapturingHotkey ? Visibility.Visible : Visibility.Collapsed;
        ShortcutChange.Content = state.CapturingHotkey ? "Cancel" : "Change";
        ShortcutSub.Text = state.CapturingHotkey ? "Press " + Hotkey.Choices + " · Esc keeps the current one"
            : state.HotkeyNote.Length > 0 ? state.HotkeyNote
            : "Right Ctrl, the Menu key or a function key also work";
        TapSwitch.IsChecked = state.TapToStart;
        BindMicrophones();
        MediaSwitch.IsChecked = state.PauseMedia;
        SoundsSwitch.IsChecked = state.SoundsEnabled;

        // Look
        BindThemeSwatches();
        PillSample.Content = DrawPill(new Palette(PillTheme.Named(state.PillTheme)), 220, 44);

        // About
        VersionText.Text = "Softly " + Updater.CurrentVersion;
        UpdateAction.Content = state.UpdateText;
        UpdateAction.IsEnabled = state.UpdatePhase is not (Updater.Phase.Checking or Updater.Phase.Downloading);
        UpdateAction.Foreground = state.UpdatePhase == Updater.Phase.UpToDate ? Green : Cobalt;
        UpdateNote.Text = state.UpdatePhase switch
        {
            Updater.Phase.Failed when state.UpdateError.Length > 0 => state.UpdateError,
            Updater.Phase.Available => "Softly " + state.UpdateVersion + " is available.",
            Updater.Phase.UpToDate => "You have the latest version.",
            _ => "Updates come from GitHub Releases.",
        };
        HookText.Text = state.HotkeyRunning ? "✓ " + key : "Not running";
        HookText.Foreground = state.HotkeyRunning ? Green : Amber;
        ModelText.Text = state.ModelText;
        binding = false;
    }

    private void NavChanged(object sender, RoutedEventArgs e)
    {
        if (HomePanel == null) return;
        var panels = new (RadioButton nav, FrameworkElement panel)[]
        {
            (NavHome, HomePanel), (NavSpeech, SpeechPanel), (NavWords, WordsPanel),
            (NavShortcut, ShortcutPanel), (NavLook, LookPanel), (NavAbout, AboutPanel),
        };
        foreach (var (nav, panel) in panels)
            panel.Visibility = nav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        if (NavShortcut.IsChecked == true) state.RefreshMicrophones();
        else if (state.CapturingHotkey) state.CancelCapture();
    }

    /// <summary>Opens a screen from outside (the tray, the control pipe).</summary>
    public void ShowSection(string name)
    {
        var nav = name switch
        {
            "speech" => NavSpeech, "words" => NavWords, "shortcut" => NavShortcut,
            "look" => NavLook, "about" => NavAbout, _ => NavHome,
        };
        nav.IsChecked = true;
    }

    // Home

    private sealed record RecentRow(string Text, DateTime At)
    {
        public string Ago
        {
            get
            {
                var s = (DateTime.Now - At).TotalSeconds;
                return s < 60 ? "just now" : s < 3600 ? $"{(int)(s / 60)} min" : $"{(int)(s / 3600)} h";
            }
        }
    }

    private void PracticeChanged(object sender, TextChangedEventArgs e)
    {
        bool empty = Practice.Text.Length == 0;
        PracticeHint.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ClearButton.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        PracticeNote.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ClearPractice(object sender, RoutedEventArgs e) => Practice.Text = "";

    private void CopyRecent(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string text) return;
        try { Clipboard.SetText(text); } catch (System.Runtime.InteropServices.COMException) { }
    }

    private void ModelActionClick(object sender, RoutedEventArgs e)
    {
        if (state.ModelStatus == Transcriber.Status.Failed) state.ReloadModel();
        else if (state.DownloadPhase == ModelDownloader.Phase.Downloading) state.CancelDownload();
        else state.DownloadModel();
    }

    // Speech

    private readonly List<(SpeechModel model, Ellipse radio, TextBlock name, TextBlock status, ProgressBar bar)> modelRows = new();

    private static string Note(SpeechModel model) => model.Id switch
    {
        "fast" => "Smallest and quickest",
        "balanced" => "Quick, good with everyday speech",
        "accurate" => "Best with names and code",
        _ => "Fast on the CPU · no hints",
    };

    /// <summary>
    /// One row per speech model: radio, name and a short note, and on the
    /// right its state. Picking one that is not on disk downloads it first;
    /// the current model keeps working until it is ready.
    /// </summary>
    private void BuildModelRows()
    {
        var all = SpeechModel.All;
        for (int i = 0; i < all.Length; i++)
        {
            var model = all[i];
            var radio = new Ellipse { Width = 18, Height = 18, VerticalAlignment = VerticalAlignment.Center };
            var name = new TextBlock { Text = model.Name, FontSize = 15, Foreground = Ink, VerticalAlignment = VerticalAlignment.Center };
            var note = new TextBlock { Text = Note(model), FontSize = 13, Foreground = Muted, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            var status = new TextBlock { FontSize = 13, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            var bar = new ProgressBar { Width = 64, Height = 4, Maximum = 1, Foreground = Cobalt, Background = Hairline, BorderThickness = new Thickness(0), Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            right.Children.Add(bar);
            right.Children.Add(status);
            var rightBox = new Grid { Width = 140, Margin = new Thickness(12, 0, 0, 0) };
            rightBox.Children.Add(right);
            var text = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(14, 0, 0, 0) };
            text.Children.Add(name);
            text.Children.Add(note);
            var dock = new DockPanel { Background = Brushes.Transparent };
            DockPanel.SetDock(radio, Dock.Left);
            DockPanel.SetDock(rightBox, Dock.Right);
            dock.Children.Add(radio);
            dock.Children.Add(rightBox);
            dock.Children.Add(text);
            var row = new Border
            {
                Child = dock, Padding = new Thickness(0, 12, 0, 12), Cursor = Cursors.Hand,
                BorderBrush = Hairline, BorderThickness = new Thickness(0, 0, 0, i < all.Length - 1 ? 1 : 0),
            };
            string id = model.Id;
            row.MouseLeftButtonUp += (_, _) =>
            {
                if (state.DownloadingModel == id && state.DownloadPhase == ModelDownloader.Phase.Downloading) state.CancelDownload();
                else if (state.SpeechModel != id) state.ChooseModel(id);
            };
            ModelList.Children.Add(row);
            modelRows.Add((model, radio, name, status, bar));
        }
    }

    private void BindModelRows()
    {
        foreach (var (model, radio, name, status, bar) in modelRows)
        {
            bool selected = model.Id == state.SpeechModel;
            bool mine = state.DownloadingModel == model.Id;
            radio.Stroke = selected ? Cobalt : Hex(0xB9BCC2);
            radio.StrokeThickness = selected ? 5 : 1.5;
            name.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Medium;
            bool downloading = mine && state.DownloadPhase == ModelDownloader.Phase.Downloading;
            bar.Visibility = downloading ? Visibility.Visible : Visibility.Collapsed;
            bar.Value = state.DownloadProgress;
            (status.Text, status.Foreground, status.FontWeight) = (mine, state.DownloadPhase) switch
            {
                (true, ModelDownloader.Phase.Downloading) => ($"{(int)(state.DownloadProgress * 100)}%", Ink, FontWeights.Normal),
                (true, ModelDownloader.Phase.Verifying) => ("Verifying…", Muted, FontWeights.Normal),
                (true, ModelDownloader.Phase.Failed) => ("Failed · Retry", Cobalt, FontWeights.Medium),
                _ when selected => (state.ModelStatus == Transcriber.Status.Loading ? "Loading…" : "In use", Cobalt, FontWeights.SemiBold),
                _ when model.IsDownloaded => ("Downloaded", Muted, FontWeights.Normal),
                _ => ($"Get · {model.SizeMB} MB", Cobalt, FontWeights.Medium),
            };
        }
    }

    private void LanguagePill(object sender, RoutedEventArgs e)
    {
        string code = sender == LangEnglish ? "en" : "auto";
        if (code != state.Language) state.ChooseLanguage(code);
    }

    private void LanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (binding || LanguageBox.SelectedItem is not ComboBoxItem item || (string)item.Tag == "") return;
        if ((string)item.Tag != state.Language) state.ChooseLanguage((string)item.Tag);
    }

    private void SubmitChanged(object sender, RoutedEventArgs e) => state.SubmitWord = SubmitSwitch.IsChecked == true;

    // Words

    private void DraftChanged(object sender, TextChangedEventArgs e) =>
        DraftHint.Visibility = Draft.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;

    private void DraftKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        var word = Draft.Text.Trim().Trim(',', '.');
        Draft.Text = "";
        if (word.Length == 0) return;
        var words = state.Vocabulary;
        if (words.Any(w => string.Equals(w, word, StringComparison.OrdinalIgnoreCase))) return;
        words.Add(word);
        state.Vocabulary = new List<string>(words);
    }

    private void RemoveWord(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string word) return;
        state.Vocabulary = state.Vocabulary.Where(w => w != word).ToList();
    }

    /// <summary>One row of the fixes list; an empty "to" reads "removed".</summary>
    private sealed record RuleRow(Replacement Rule)
    {
        public string From => Rule.From;
        public string Shown => Rule.To.Length == 0 ? "removed" : Rule.To;
        public FontWeight Weight => Rule.To.Length == 0 ? FontWeights.Normal : FontWeights.Medium;
        public FontStyle Style => Rule.To.Length == 0 ? FontStyles.Italic : FontStyles.Normal;
        public Brush Brush => Rule.To.Length == 0 ? Faint : Ink;
    }

    private void RuleDraftChanged(object sender, TextChangedEventArgs e)
    {
        HeardHint.Visibility = HeardBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        TypedHint.Visibility = TypedBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        AddRuleButton.IsEnabled = HeardBox.Text.Trim().Length > 0;
    }

    private void RuleKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { AddRule(sender, e); e.Handled = true; }
    }

    private void AddRule(object sender, RoutedEventArgs e)
    {
        var from = HeardBox.Text.Trim();
        if (from.Length == 0) return;
        // A new fix for the same phrase replaces the old one.
        var rules = state.Replacements.Where(r => !string.Equals(r.From, from, StringComparison.OrdinalIgnoreCase)).ToList();
        rules.Add(new Replacement(from, TypedBox.Text.Trim()));
        state.Replacements = rules;
        HeardBox.Text = TypedBox.Text = "";
        HeardBox.Focus();
    }

    private void RemoveRule(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not RuleRow row) return;
        state.Replacements = state.Replacements.Where(r => r != row.Rule).ToList();
    }

    // Shortcut

    private void ChangeShortcut(object sender, RoutedEventArgs e)
    {
        if (state.CapturingHotkey) state.CancelCapture(); else state.CaptureHotkey();
    }

    private void TapChanged(object sender, RoutedEventArgs e) => state.TapToStart = TapSwitch.IsChecked == true;
    private void MediaChanged(object sender, RoutedEventArgs e) => state.PauseMedia = MediaSwitch.IsChecked == true;
    private void SoundsChanged(object sender, RoutedEventArgs e) => state.SoundsEnabled = SoundsSwitch.IsChecked == true;

    private void BindMicrophones()
    {
        var wanted = new List<(string id, string name)> { ("", "System default") };
        wanted.AddRange(state.Microphones.Select(m => (m.Id, m.Name)));
        var have = MicBox.Items.Cast<ComboBoxItem>().Select(i => ((string)i.Tag, (string)i.Content)).ToList();
        if (!have.SequenceEqual(wanted))
        {
            MicBox.Items.Clear();
            foreach (var (id, name) in wanted) MicBox.Items.Add(new ComboBoxItem { Content = name, Tag = id });
        }
        MicBox.SelectedItem = MicBox.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == state.Microphone)
                              ?? MicBox.Items[0];
    }

    private void MicChanged(object sender, SelectionChangedEventArgs e)
    {
        if (binding || MicBox.SelectedItem is not ComboBoxItem item) return;
        state.Microphone = (string)item.Tag;
    }

    // Look

    private void PreviewClick(object sender, RoutedEventArgs e) => state.PreviewPill();

    private readonly List<(string id, Border cell, Ellipse ring, TextBlock label)> themeSwatches = new();

    /// <summary>Each style as its background dot with the accent inside, and its name.</summary>
    private void BuildThemeSwatches()
    {
        foreach (var theme in PillTheme.All)
        {
            var palette = new Palette(theme);
            var dot = new Grid { Width = 22, Height = 22 };
            dot.Children.Add(new Ellipse { Fill = palette.Background.Brush });
            var ring = new Ellipse { StrokeThickness = 1, Stroke = palette.IsLight ? Hex(0xD5D7DB) : Brushes.Transparent };
            dot.Children.Add(ring);
            dot.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = palette.Accent.Brush });
            var label = new TextBlock { Text = theme.Name, FontSize = 13, Foreground = Ink, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(dot);
            row.Children.Add(label);
            var cell = new Border { Child = row, Width = 124, Padding = new Thickness(8, 6, 8, 6), Margin = new Thickness(0, 0, 4, 6), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand, Background = Brushes.Transparent, ToolTip = theme.Name + " pill" };
            string id = theme.Id;
            cell.MouseLeftButtonUp += (_, _) =>
            {
                if (state.PillTheme == id) return;
                state.PillTheme = id;
                state.PreviewPill();
            };
            ThemeGrid.Children.Add(cell);
            themeSwatches.Add((id, cell, ring, label));
        }
    }

    private void BindThemeSwatches()
    {
        foreach (var (id, cell, ring, label) in themeSwatches)
        {
            bool selected = id == state.PillTheme;
            cell.Background = selected ? CobaltWash : Brushes.Transparent;
            label.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
            if (selected) { ring.Stroke = Cobalt; ring.StrokeThickness = 2; }
            else
            {
                var light = new Palette(PillTheme.Named(id)).IsLight;
                ring.Stroke = light ? Hex(0xD5D7DB) : Brushes.Transparent;
                ring.StrokeThickness = 1;
            }
        }
    }

    /// <summary>A still drawing of the pill mid-recording.</summary>
    private static FrameworkElement DrawPill(Palette palette, double width, double height)
    {
        var glow = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 0) };
        glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0).Color, 0));
        glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0.5).Color, 0.5));
        glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0).Color, 1));
        var bars = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        foreach (double h in new[] { 6.0, 12, 18, 10, 15, 8, 5 })
            bars.Children.Add(new Border { Width = 2, Height = h, CornerRadius = new CornerRadius(1), Background = palette.Foreground.Brush, Margin = new Thickness(1.5, 0, 1.5, 0) });
        var groove = new Grid { Height = height - 14, Margin = new Thickness(7, 0, 8, 0) };
        groove.Children.Add(new Border { CornerRadius = new CornerRadius((height - 14) / 2), Background = palette.Floor.Brush });
        groove.Children.Add(new Border { CornerRadius = new CornerRadius((height - 14) / 2), Background = glow });
        groove.Children.Add(bars);
        var time = new TextBlock { Text = "0:07", FontSize = 12, Foreground = palette.Foreground.Brush, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0) };
        var dock = new DockPanel();
        DockPanel.SetDock(time, Dock.Right);
        dock.Children.Add(time);
        dock.Children.Add(groove);
        return new Border
        {
            Width = width, Height = height, CornerRadius = new CornerRadius(height / 2), Background = palette.Background.Brush, Child = dock,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 30, ShadowDepth = 10, Direction = 270, Opacity = 0.25 },
        };
    }

    // About

    private void UpdateActionClick(object sender, RoutedEventArgs e)
    {
        if (state.UpdatePhase == Updater.Phase.Available) state.InstallUpdate(); else state.CheckForUpdates();
    }

    private void ShowModelsClick(object sender, RoutedEventArgs e) => state.ShowModelFolder();

    private void SourceClick(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/denonmaryland/softly") { UseShellExecute = true });
}
