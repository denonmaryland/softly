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
        MediaSwitch.IsChecked = state.PauseMedia;
        ModelText.Text = state.ModelText;
        ModelText.Foreground = state.ModelStatus == Transcriber.Status.Ready ? Green : Muted;
        bool trouble = state.ModelStatus is Transcriber.Status.MissingModel or Transcriber.Status.Failed;
        ModelAction.Visibility = trouble ? Visibility.Visible : Visibility.Collapsed;
        ModelAction.Content = state.ModelStatus == Transcriber.Status.Failed ? "Reload" : "Show Model Folder";
        HookText.Text = state.HotkeyRunning ? "✓ Right Alt is reserved for Softly while it runs" : "○ The keyboard hook could not start; restart Softly";
        HookText.Foreground = state.HotkeyRunning ? Green : Muted;
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
    private void MediaChanged(object sender, RoutedEventArgs e) => state.PauseMedia = MediaSwitch.IsChecked == true;

    private void ModelActionClick(object sender, RoutedEventArgs e)
    {
        if (state.ModelStatus == Transcriber.Status.Failed) state.ReloadModel(); else state.ShowModelFolder();
    }
}
