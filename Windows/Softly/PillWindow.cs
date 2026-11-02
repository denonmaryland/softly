using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Softly;

/// <summary>
/// Borderless, transparent, non-activating window: it floats over everything
/// but never takes focus, so the app you are dictating into keeps focus and
/// receives the paste.
/// </summary>
public sealed class PillWindow : Window
{
    private readonly PillSurface surface;

    public PillWindow(PillModel model)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        Width = PillGeometry.PanelSize.Width;
        Height = PillGeometry.PanelSize.Height;
        Title = "Softly";
        surface = new PillSurface(model);
        Content = surface;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            int style = GetWindowLong(handle, GWL_EXSTYLE);
            SetWindowLong(handle, GWL_EXSTYLE, style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
        };
        model.PointerLocation = PointerInPill;
    }

    /// <summary>Bottom-centre of the screen under the pointer, above the taskbar.</summary>
    public void Present()
    {
        var cursor = System.Windows.Forms.Cursor.Position;
        var screen = System.Windows.Forms.Screen.FromPoint(cursor);
        var area = screen.WorkingArea;
        double scale = 1;
        var source = PresentationSource.FromVisual(this);
        if (source?.CompositionTarget != null) scale = source.CompositionTarget.TransformToDevice.M11;
        else scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        Left = Math.Round((area.Left + area.Width / 2.0) / scale - PillGeometry.PanelSize.Width / 2);
        Top = Math.Round(area.Bottom / scale - PillGeometry.PanelSize.Height - PillGeometry.BottomMargin);
        if (!IsVisible) Show();
        surface.Running = true;
    }

    /// <summary>
    /// Builds the window, its layered surface and the renderer once, off
    /// screen, so the first key press after launch does not pay for it.
    /// </summary>
    public void WarmUp()
    {
        if (IsVisible) return;
        Left = -20000;
        Top = -20000;
        Show();
        UpdateLayout();
        Hide();
    }

    public void Dismiss()
    {
        surface.Running = false;
        if (IsVisible) Hide();
    }

    /// <summary>Polled each frame: hover works even though this window is never active.</summary>
    private Point? PointerInPill()
    {
        if (!IsVisible) return null;
        if (!GetCursorPos(out var p)) return null;
        var local = surface.PointFromScreen(new Point(p.X, p.Y));
        if (local.X < 0 || local.Y < 0 || local.X > Width || local.Y > Height) return null;
        return local;
    }

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x00000080;

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
}

/// <summary>Redraws the pill every frame while it is on screen.</summary>
public sealed class PillSurface : FrameworkElement
{
    private readonly PillModel model;
    private readonly PillRenderer renderer = new();
    private bool running;
    private Point pressStart;

    public PillSurface(PillModel model)
    {
        this.model = model;
        Width = PillGeometry.PanelSize.Width;
        Height = PillGeometry.PanelSize.Height;
        MouseLeftButtonDown += (_, e) =>
        {
            pressStart = e.GetPosition(this);
            model.PointerDown(pressStart);
            CaptureMouse();
        };
        MouseLeftButtonUp += (_, e) =>
        {
            ReleaseMouseCapture();
            model.PointerUp(e.GetPosition(this), pressStart);
        };
    }

    public bool Running
    {
        get => running;
        set
        {
            if (running == value) return;
            running = value;
            if (value) CompositionTarget.Rendering += OnRendering;
            else CompositionTarget.Rendering -= OnRendering;
            InvalidateVisual();
        }
    }

    private void OnRendering(object? sender, EventArgs e) => InvalidateVisual();

    protected override void OnRender(DrawingContext dc)
    {
        var frame = model.NextFrame();
        renderer.Draw(dc, frame, VisualTreeHelper.GetDpi(this).PixelsPerDip);
    }
}
