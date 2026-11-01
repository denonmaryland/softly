using Windows.Media.Control;

namespace Softly;

/// <summary>
/// Pauses whatever is playing while recording and resumes only what it
/// paused, like Voxtype's pause_media on Linux. Uses the system media
/// session manager, so it covers Spotify, browsers, Music and the rest.
/// </summary>
public sealed class MediaPauser
{
    public static readonly MediaPauser Shared = new();
    private readonly List<string> paused = new();
    private readonly object gate = new();

    public void Pause()
    {
        if (!Settings.PauseMedia) return;
        _ = Task.Run(async () =>
        {
            try
            {
                var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
                foreach (var session in manager.GetSessions())
                {
                    var info = session.GetPlaybackInfo();
                    if (info.PlaybackStatus != GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing) continue;
                    if (await session.TryPauseAsync())
                        lock (gate) paused.Add(session.SourceAppUserModelId);
                }
            }
            catch (Exception) { }
        });
    }

    public void Resume()
    {
        List<string> names;
        lock (gate)
        {
            names = new List<string>(paused);
            paused.Clear();
        }
        if (names.Count == 0) return;
        _ = Task.Run(async () =>
        {
            try
            {
                var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
                foreach (var session in manager.GetSessions())
                    if (names.Contains(session.SourceAppUserModelId)) await session.TryPlayAsync();
            }
            catch (Exception) { }
        });
    }
}
