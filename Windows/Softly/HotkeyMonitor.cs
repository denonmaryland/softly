using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Global key handling through a low-level keyboard hook.
///
/// Trigger: Right Alt, alone. It is swallowed entirely so apps never see a
/// bare Alt press (which would otherwise focus their menu bar). Esc is
/// swallowed only while the pill is showing. Any other key pressed while
/// Right Alt is held is reported as a chord so a stray recording is discarded.
/// </summary>
public sealed class HotkeyMonitor : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105;
    private const uint VK_RMENU = 0xA5, VK_ESCAPE = 0x1B;
    private const uint LLKHF_INJECTED = 0x10;

    public Action OnPress = () => { };
    public Action OnRelease = () => { };
    public Action OnChord = () => { };
    /// <summary>Return true to swallow Esc.</summary>
    public Func<bool> OnEscape = () => false;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private readonly LowLevelKeyboardProc callback; // kept alive for the hook's lifetime
    private readonly Dispatcher dispatcher;
    private IntPtr hook;
    private volatile bool triggerDown;
    private Thread? thread;
    private uint threadId;

    public bool IsRunning => hook != IntPtr.Zero;
    /// <summary>When the last trigger press arrived, for latency logging.</summary>
    public long PressTicks { get; private set; }

    public HotkeyMonitor(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        callback = Handle;
    }

    /// <summary>
    /// Installs the hook on a dedicated high-priority thread with its own
    /// message loop. Windows calls a low-level hook on the thread that
    /// installed it and holds every keystroke on the system until it returns,
    /// so it must not share the UI thread: when the PC is busy, a starved UI
    /// thread made the trigger (and all typing) lag.
    /// </summary>
    public bool Start()
    {
        if (hook != IntPtr.Zero) return true;
        using var ready = new ManualResetEventSlim();
        thread = new Thread(() =>
        {
            threadId = GetCurrentThreadId();
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, callback, GetModuleHandle(null), 0);
            ready.Set();
            if (hook == IntPtr.Zero) return;
            while (GetMessage(out MSG msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        })
        {
            IsBackground = true,
            Priority = ThreadPriority.Highest,
            Name = "Softly keyboard hook",
        };
        thread.Start();
        ready.Wait(3000);
        return hook != IntPtr.Zero;
    }

    public void Dispose()
    {
        if (threadId != 0) PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode, scanCode, flags, time;
        public IntPtr dwExtraInfo;
    }

    /// <summary>Runs on the hook thread; anything slow goes to the UI dispatcher.</summary>
    private IntPtr Handle(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(hook, nCode, wParam, lParam);
        var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        int msg = (int)wParam;
        bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
        bool up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
        bool injected = (k.flags & LLKHF_INJECTED) != 0 || k.dwExtraInfo == Paster.InjectedMarker;

        if (k.vkCode == VK_RMENU && !injected)
        {
            if (down && !triggerDown)
            {
                triggerDown = true;
                PressTicks = System.Diagnostics.Stopwatch.GetTimestamp();
                dispatcher.BeginInvoke(DispatcherPriority.Send, OnPress);
            }
            else if (up && triggerDown)
            {
                triggerDown = false;
                dispatcher.BeginInvoke(DispatcherPriority.Send, OnRelease);
            }
            return (IntPtr)1;
        }
        if (down && !injected)
        {
            // Esc decides here whether the key is swallowed; OnEscape must be quick.
            if (k.vkCode == VK_ESCAPE && OnEscape()) return (IntPtr)1;
            if (triggerDown) dispatcher.BeginInvoke(OnChord);
        }
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    private const uint WM_QUIT = 0x0012;
    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam, lParam;
        public uint time;
        public int x, y;
    }
    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG msg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG msg);
    [DllImport("user32.dll")]
    private static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr wParam, IntPtr lParam);
}
