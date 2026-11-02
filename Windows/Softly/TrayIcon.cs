using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Softly;

/// <summary>Notification-area icon and menu; the only chrome when the window is closed.</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon icon = new();
    private readonly AppState state;
    private readonly ToolStripMenuItem status = new() { Enabled = false };
    private readonly ToolStripMenuItem sounds = new("Play Sounds") { CheckOnClick = true };
    private readonly ToolStripMenuItem updates = new("Check for Updates…");
    private readonly ToolStripMenuItem download = new($"Download Speech Model ({ModelDownloader.SizeMB} MB)");
    private readonly ToolStripMenuItem modelFolder = new("Show Model Folder");
    private readonly ToolStripMenuItem reload = new("Reload Model");
    private readonly ToolStripSeparator modelSeparator = new();
    private Icon? readyIcon, warnIcon;

    public Action OpenWindow = () => { };
    public Action Quit = () => { };

    public TrayIcon(AppState state)
    {
        this.state = state;
        var menu = new ContextMenuStrip();
        menu.Items.Add(status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open Softly…", null, (_, _) => OpenWindow());
        updates.Click += (_, _) => { if (state.UpdatePhase == Updater.Phase.Available) state.InstallUpdate(); else { state.CheckForUpdates(); OpenWindow(); } };
        menu.Items.Add(updates);
        menu.Items.Add("Preview Pill", null, (_, _) => state.PreviewPill());
        sounds.Click += (_, _) => state.SoundsEnabled = sounds.Checked;
        menu.Items.Add(sounds);
        menu.Items.Add(modelSeparator);
        download.Click += (_, _) => { state.DownloadModel(); OpenWindow(); };
        menu.Items.Add(download);
        modelFolder.Click += (_, _) => state.ShowModelFolder();
        reload.Click += (_, _) => state.ReloadModel();
        menu.Items.Add(modelFolder);
        menu.Items.Add(reload);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit Softly", null, (_, _) => Quit());
        menu.Opening += (_, _) => Refresh();
        icon.ContextMenuStrip = menu;
        icon.Text = "Softly";
        icon.DoubleClick += (_, _) => OpenWindow();
        icon.Visible = true;
        state.PropertyChanged += (_, _) => Refresh();
        Refresh();
    }

    public void Refresh()
    {
        status.Text = state.StatusLine;
        sounds.Checked = state.SoundsEnabled;
        updates.Text = state.UpdatePhase == Updater.Phase.Available ? "Update to Softly " + state.UpdateVersion + "…" : "Check for Updates…";
        bool modelTrouble = state.ModelStatus != Transcriber.Status.Ready;
        modelFolder.Visible = reload.Visible = modelSeparator.Visible = modelTrouble;
        download.Visible = state.ModelStatus == Transcriber.Status.MissingModel && state.DownloadPhase == ModelDownloader.Phase.Idle;
        icon.Icon = state.Ready ? readyIcon ??= Draw(false) : warnIcon ??= Draw(true);
        icon.Text = "Softly · " + state.StatusLine;
    }

    /// <summary>A small waveform, with an amber dot while something still needs attention.</summary>
    private static Icon Draw(bool warn)
    {
        using var bmp = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);
        int[] heights = { 8, 16, 26, 14, 20, 10 };
        using var pen = new Pen(Color.White, 3) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        for (int i = 0; i < heights.Length; i++)
        {
            float x = 4 + i * 4.8f;
            g.DrawLine(pen, x, 16 - heights[i] / 2f, x, 16 + heights[i] / 2f);
        }
        if (warn)
        {
            using var brush = new SolidBrush(Color.FromArgb(255, 214, 143, 0));
            g.FillEllipse(brush, 20, 20, 11, 11);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
