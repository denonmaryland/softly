using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;

namespace Softly;

/// <summary>
/// Puts the transcript on the clipboard and sends Ctrl+V to the foreground
/// app. The transcript stays on the clipboard afterwards, so it can be
/// pasted again if the field didn't accept it.
/// </summary>
public static class Paster
{
    /// <summary>Tags our synthetic keys so the hotkey hook ignores them.</summary>
    public static readonly IntPtr InjectedMarker = (IntPtr)0x50F7;

    public static void Paste(string text, Dispatcher dispatcher)
    {
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(text, true);
                break;
            }
            catch (COMException)
            {
                Thread.Sleep(20);
            }
        }
        // Give the clipboard a moment to publish before the shortcut.
        var timer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(30) };
        timer.Tick += (_, _) => { timer.Stop(); SendControlV(); };
        timer.Start();
    }

    private const ushort VK_CONTROL = 0x11, VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private static void SendControlV()
    {
        var inputs = new[]
        {
            Key(VK_CONTROL, false), Key(VK_V, false), Key(VK_V, true), Key(VK_CONTROL, true),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT Key(ushort vk, bool up) => new()
    {
        type = 1,
        u = new InputUnion
        {
            ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0, dwExtraInfo = InjectedMarker },
        },
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion u; }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
