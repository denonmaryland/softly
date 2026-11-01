namespace Softly.Core;

// Key gesture state machine, the same rules as the Mac app's
// GestureController.swift and the Linux plugin's Controller.js.
//
//  Hold the key     -> record while held, transcribe on release.
//  Double-tap       -> latch hands-free; press again to finish.
//  Quick single tap -> waits DoubleTapWindow for a second press, then stops.

public enum RecorderState { Idle, Recording, Transcribing }

public enum GestureEvent { Press, Release, Toggle, Timeout, Reset, Stop, Cancel }

public enum GestureAction { Start, Stop, Cancel, TimerStart, TimerStop }

public sealed class GestureController
{
    /// <summary>Releases faster than this (seconds) count as a tap.</summary>
    public const double TapLimit = 0.240;
    /// <summary>A second press within this window after a tap latches hands-free mode.</summary>
    public const double DoubleTapWindow = 0.330;

    public bool Held { get; private set; }
    public bool Locked { get; private set; }
    public bool Owned { get; private set; }
    public bool Waiting { get; private set; }
    private bool ignoreRelease;
    private double pressedAt;
    private double releasedAt;

    /// <param name="now">Monotonic seconds.</param>
    /// <param name="state">The recorder state as currently known to the adapter.</param>
    public List<GestureAction> Send(GestureEvent e, double now, RecorderState state)
    {
        var o = new List<GestureAction>();
        switch (e)
        {
            case GestureEvent.Reset:
                Locked = false; Owned = false; Waiting = false;
                ignoreRelease = Held;
                o.Add(GestureAction.TimerStop);
                break;
            case GestureEvent.Stop:
            case GestureEvent.Cancel:
                Locked = false; Owned = false; Waiting = false;
                ignoreRelease = Held;
                o.Add(GestureAction.TimerStop);
                o.Add(e == GestureEvent.Stop ? GestureAction.Stop : GestureAction.Cancel);
                break;
            case GestureEvent.Toggle:
                if (Owned || state == RecorderState.Recording) return Send(GestureEvent.Stop, now, state);
                if (state != RecorderState.Idle) return o;
                Owned = true; Locked = true;
                o.Add(GestureAction.Start);
                break;
            case GestureEvent.Press:
                if (Held) return o;
                Held = true;
                pressedAt = now;
                if (Waiting && now - releasedAt <= DoubleTapWindow)
                {
                    Waiting = false;
                    Locked = true;
                    o.Add(GestureAction.TimerStop);
                }
                else if (Locked || (!Owned && state == RecorderState.Recording))
                {
                    ignoreRelease = true;
                    o = Send(GestureEvent.Stop, now, state);
                }
                else if (state == RecorderState.Idle && !Owned)
                {
                    Owned = true;
                    o.Add(GestureAction.Start);
                }
                else
                {
                    ignoreRelease = true;
                }
                break;
            case GestureEvent.Release:
                if (!Held) return o;
                Held = false;
                if (ignoreRelease) { ignoreRelease = false; return o; }
                if (Locked || !Owned) return o;
                if (now - pressedAt <= TapLimit)
                {
                    Waiting = true;
                    releasedAt = now;
                    o.Add(GestureAction.TimerStart);
                }
                else
                {
                    Owned = false;
                    o.Add(GestureAction.Stop);
                }
                break;
            case GestureEvent.Timeout:
                if (Waiting)
                {
                    Waiting = false; Owned = false;
                    o.Add(GestureAction.Stop);
                }
                break;
        }
        return o;
    }
}
