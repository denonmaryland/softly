using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Softly;

/// <summary>
/// Home, Vocabulary and Preferences behind a sidebar: the same window the
/// Mac app has (Paper "01 Quiet Native"), in WPF.
/// </summary>
public partial class MainWindow : Window
{
    private readonly AppState state;
    private static readonly Brush Green = new SolidColorBrush(Color.FromRgb(0x27, 0x83, 0x4A));
    private static readonly Brush Muted = new SolidColorBrush(Color.FromRgb(0x65, 0x70, 0x7C));

    public MainWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        state.PropertyChanged += OnStateChanged;
        Closing += (_, e) =>
        {
            // Closing hides; the tray keeps the app alive.
            e.Cancel = true;
            Hide();
        };
        BuildThemeSwatches();
        Bind();
    }

    private void OnStateChanged(object? sender, PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(Bind);

    private void Bind()
    {
        bool ready = state.Ready;
        StatusDot.Fill = ready ? Green : Muted;
        StatusText.Foreground = ready ? Green : Muted;
        StatusText.Text = ready ? "Ready to dictate" : state.StatusLine;
        SoundsSwitch.IsChecked = state.SoundsEnabled;
        TapSwitch.IsChecked = state.TapToStart;
        ShortcutSub.Text = state.TapToStart ? "Tap to start and stop · or hold to talk" : "Hold to talk · let go to finish";
        HomeGestureText.Text = state.TapToStart ? "Tap to start, tap again to finish. Or hold to talk." : "Hold the key while you talk, then let go.";
        MediaSwitch.IsChecked = state.PauseMedia;
        ModelText.Text = state.ModelText;
        ModelText.Foreground = state.ModelStatus == Transcriber.Status.Ready ? Green : Muted;
        string modelAction = state.ModelActionText;
        ModelAction.Visibility = modelAction.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        ModelAction.Content = modelAction;
        HomeModelAction.Visibility = state.ModelStatus == Transcriber.Status.MissingModel && modelAction.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        HomeModelAction.Content = modelAction;
        ModelNote.Text = state.DownloadError;
        ModelNote.Visibility = state.DownloadPhase == ModelDownloader.Phase.Failed && state.DownloadError.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        HookText.Text = state.HotkeyRunning ? "✓ Right Alt is reserved for Softly while it runs" : "○ The keyboard hook could not start; restart Softly";
        HookText.Foreground = state.HotkeyRunning ? Green : Muted;
        foreach (var (id, ring, label) in themeSwatches)
        {
            bool selected = id == state.PillTheme;
            ring.BorderBrush = selected ? (Brush)FindResource("Accent") : Brushes.Transparent;
            label.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
            label.Foreground = selected ? (Brush)FindResource("Ink") : Muted;
        }
        WordList.ItemsSource = state.Vocabulary;
        PromptText.Text = state.PromptText;
        VersionText.Text = "Softly " + Updater.CurrentVersion + " · checked quietly every few hours";
        UpdateAction.Content = state.UpdateText;
        UpdateAction.IsEnabled = state.UpdatePhase is not (Updater.Phase.Checking or Updater.Phase.Downloading);
        UpdateAction.Foreground = state.UpdatePhase == Updater.Phase.UpToDate ? Green
            : state.UpdatePhase is Updater.Phase.Checking or Updater.Phase.Downloading ? Muted
            : (Brush)FindResource("Accent");
        UpdateNote.Text = state.UpdateError;
        UpdateNote.Visibility = state.UpdatePhase == Updater.Phase.Failed && state.UpdateError.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateActionClick(object sender, RoutedEventArgs e)
    {
        if (state.UpdatePhase == Updater.Phase.Available) state.InstallUpdate(); else state.CheckForUpdates();
    }

    private void NavChanged(object sender, RoutedEventArgs e)
    {
        if (HomePanel == null) return;
        bool home = NavHome.IsChecked == true, vocab = NavVocabulary.IsChecked == true;
        HomePanel.Visibility = home ? Visibility.Visible : Visibility.Collapsed;
        VocabularyPanel.Visibility = vocab ? Visibility.Visible : Visibility.Collapsed;
        PreferencesPanel.Visibility = !home && !vocab ? Visibility.Visible : Visibility.Collapsed;
        HeaderTitle.Text = home ? "Home" : vocab ? "Vocabulary" : "Preferences";
    }

    // Home

    private void PracticeChanged(object sender, TextChangedEventArgs e)
    {
        bool empty = Practice.Text.Length == 0;
        PracticeHint.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ClearButton.IsEnabled = !empty;
    }

    private void ClearPractice(object sender, RoutedEventArgs e) => Practice.Text = "";

    // Vocabulary

    private void DraftChanged(object sender, TextChangedEventArgs e) => AddButton.IsEnabled = Draft.Text.Trim().Length > 0;

    private void DraftKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { AddWord(sender, e); e.Handled = true; }
    }

    private void AddWord(object sender, RoutedEventArgs e)
    {
        var word = Draft.Text.Trim();
        if (word.Length == 0) return;
        var words = state.Vocabulary;
        if (!words.Any(w => string.Equals(w, word, StringComparison.OrdinalIgnoreCase)))
        {
            words.Add(word);
            state.Vocabulary = words;
        }
        Draft.Text = "";
    }

    private void RemoveWord(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string word) return;
        var words = state.Vocabulary;
        words.RemoveAll(w => w == word);
        state.Vocabulary = words;
    }

    // Preferences

    private void SoundsChanged(object sender, RoutedEventArgs e) => state.SoundsEnabled = SoundsSwitch.IsChecked == true;
    private void TapChanged(object sender, RoutedEventArgs e) => state.TapToStart = TapSwitch.IsChecked == true;
    private void MediaChanged(object sender, RoutedEventArgs e) => state.PauseMedia = MediaSwitch.IsChecked == true;

    private void PreviewClick(object sender, RoutedEventArgs e) => state.PreviewPill();

    private readonly List<(string id, Border ring, TextBlock label)> themeSwatches = new();

    /// <summary>
    /// One small pill per style: capsule, groove, backlight and a few bars.
    /// Picking one saves it and plays the silent preview.
    /// </summary>
    private void BuildThemeSwatches()
    {
        foreach (var theme in PillTheme.All)
        {
            var palette = new Palette(theme);
            var bg = palette.Background;
            var face = new LinearGradientBrush(bg.Lighter(palette.IsLight ? 1.03 : 1.13).Color, bg.Darker(1.1).Color, 90);
            var glow = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 0) };
            glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0).Color, 0));
            glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0.55).Color, 0.5));
            glow.GradientStops.Add(new GradientStop(palette.Accent.Alpha(0).Color, 1));

            var bars = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            foreach (double h in new[] { 5.0, 9, 13, 8, 11, 6, 4 })
                bars.Children.Add(new Border { Width = 2, Height = h, CornerRadius = new CornerRadius(1), Background = palette.Foreground.Brush, Margin = new Thickness(1.5, 0, 1.5, 0) });
            var groove = new Grid { Margin = new Thickness(4, 4, 26, 4) };
            groove.Children.Add(new Border { CornerRadius = new CornerRadius(9), Background = palette.Floor.Brush });
            groove.Children.Add(new Border { CornerRadius = new CornerRadius(9), Background = glow });
            groove.Children.Add(bars);
            var capsule = new Grid { Width = 96, Height = 26 };
            capsule.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(13), Background = face,
                BorderBrush = new RGBA(0, 0, 0, palette.IsLight ? 0.12 : 0.4).Brush, BorderThickness = new Thickness(1),
            });
            capsule.Children.Add(groove);
            capsule.Children.Add(new System.Windows.Shapes.Ellipse
            {
                Width = 4, Height = 4, Fill = palette.Foreground.Alpha(0.76).Brush,
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0),
            });

            var ring = new Border { Child = capsule, Padding = new Thickness(5), CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(2), BorderBrush = Brushes.Transparent };
            var label = new TextBlock { Text = theme.Name, FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
            var cell = new StackPanel { Width = 118, Margin = new Thickness(0, 0, 6, 14), Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = theme.Name + " pill" };
            cell.Children.Add(ring);
            cell.Children.Add(label);
            string id = theme.Id;
            cell.MouseLeftButtonUp += (_, _) =>
            {
                if (state.PillTheme == id) return;
                state.PillTheme = id;
                state.PreviewPill();
            };
            ThemeGrid.Children.Add(cell);
            themeSwatches.Add((id, ring, label));
        }
    }

    private void ModelActionClick(object sender, RoutedEventArgs e)
    {
        if (state.ModelStatus == Transcriber.Status.Failed) state.ReloadModel();
        else if (state.DownloadPhase == ModelDownloader.Phase.Downloading) state.CancelDownload();
        else state.DownloadModel();
    }
}
