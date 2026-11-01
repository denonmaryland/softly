using System.IO;
using System.Media;

namespace Softly;

/// <summary>The same short open/close cues as the Mac app and the Linux pill.</summary>
public static class Sounds
{
    private static readonly SoundPlayer? Open = Load("open");
    private static readonly SoundPlayer? Close = Load("close");

    private static SoundPlayer? Load(string name)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Sounds", name + ".wav");
        if (!File.Exists(path)) return null;
        try
        {
            var player = new SoundPlayer(path);
            player.Load();
            return player;
        }
        catch (Exception) { return null; }
    }

    public static void PlayOpen() => Play(Open);
    public static void PlayClose() => Play(Close);

    private static void Play(SoundPlayer? sound)
    {
        if (!Settings.SoundsEnabled || sound == null) return;
        try { sound.Play(); } catch (Exception) { }
    }
}
