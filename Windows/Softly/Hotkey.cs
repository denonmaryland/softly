namespace Softly;

/// <summary>
/// A key that can start dictation on its own: a right-hand modifier or a
/// function key, named by its Windows virtual-key code.
/// </summary>
public sealed record Hotkey(uint Vk, string Name)
{
    public static readonly Hotkey RightAlt = new(0xA5, "Right Alt");

    public static readonly IReadOnlyList<Hotkey> All = BuildAll();

    private static List<Hotkey> BuildAll()
    {
        var keys = new List<Hotkey> { RightAlt, new(0xA3, "Right Ctrl"), new(0x5C, "Right Win") };
        for (uint i = 0; i < 24; i++) keys.Add(new(0x70 + i, "F" + (i + 1)));
        return keys;
    }

    public static Hotkey? WithVk(uint vk) => All.FirstOrDefault(k => k.Vk == vk);

    public static Hotkey Current => WithVk(Settings.HotkeyVk) ?? RightAlt;

    /// <summary>Said when someone presses a key that can't be used.</summary>
    public const string Choices = "Right Alt, Right Ctrl, Right Win or a function key";
}
