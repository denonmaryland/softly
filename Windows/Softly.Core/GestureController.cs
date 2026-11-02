namespace Softly.Core;

// Key gesture state machine, the same rules as the Mac app's
// GestureController.swift and the Linux plugin's Controller.js.
//
//  Tap the key  -> start hands-free; tap again to finish.
//  Hold the key -> record while held, transcribe on release.

public enum RecorderState { Idle, Recording, Transcribing }

public enum GestureEvent { Press, Release, Toggle, Reset, Stop, Cancel }

public enum GestureAction { Start, Stop, Cancel }

public sealed class GestureController
{
    /// <summary>Presses shorter than this (seconds) are taps and keep recording hands-free;
    /// longer ones are push-to-talk and finish on release.</summary>
    public const double HoldThreshold = 0.5;

    public bool Held { get; private set; }
    public bool Locked { get; private set; }
    public bool Owned { get; private set; }
    private bool ignoreRelease;
    private double pressedAt;

    /// <param name="now">Monotonic seconds.</param>
    /// <param name="state">The recorder state as currently known to the adapter.</param>
    public List<GestureAction> Send(GestureEvent e, double now, RecorderState state)
    {
        switch (e)
        {
            case GestureEvent.Reset:
                Locked = false; Owned = false;
                ignoreRelease = Held;
                return new();
            case GestureEvent.Stop:
            case GestureEvent.Cancel:
                Locked = false; Owned = false;
                ignoreRelease = Held;
                return new() { e == GestureEvent.Stop ? GestureAction.Stop : GestureAction.Cancel };
            case GestureEvent.Toggle:
                if (Owned || state == RecorderState.Recording) return Send(GestureEvent.Stop, now, state);
                if (state != RecorderState.Idle) return new();
                Owned = true; Locked = true;
                return new() { GestureAction.Start };
            case GestureEvent.Press:
                if (Held) return new();
                Held = true;
                pressedAt = now;
                if (Locked || (!Owned && state == RecorderState.Recording))
                {
                    ignoreRelease = true;
                    return Send(GestureEvent.Stop, now, state);
                }
                if (state == RecorderState.Idle && !Owned)
                {
                    Owned = true;
                    return new() { GestureAction.Start };
                }
                ignoreRelease = true;
                return new();
            case GestureEvent.Release:
                if (!Held) return new();
                Held = false;
                if (ignoreRelease) { ignoreRelease = false; return new(); }
                if (Locked || !Owned) return new();
                if (now - pressedAt < HoldThreshold)
                {
                    Locked = true;
                    return new();
                }
                Owned = false;
                return new() { GestureAction.Stop };
        }
        return new();
    }
}
