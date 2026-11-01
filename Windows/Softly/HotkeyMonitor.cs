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
    private bool triggerDown;

    public bool IsRunning => hook != IntPtr.Zero;

    public HotkeyMonitor(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        callback = Handle;
    }

    public bool Start()
    {
        if (hook != IntPtr.Zero) return true;
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, callback, GetModuleHandle(null), 0);
        return hook != IntPtr.Zero;
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode, scanCode, flags, time;
        public IntPtr dwExtraInfo;
    }

    /// <summary>Runs on the UI thread (the thread that installed the hook).</summary>
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
                dispatcher.BeginInvoke(OnPress);
            }
            else if (up && triggerDown)
            {
                triggerDown = false;
                dispatcher.BeginInvoke(OnRelease);
            }
            return (IntPtr)1;
        }
        if (down && !injected)
        {
            // Esc stays synchronous: it decides whether the key is swallowed.
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
}
