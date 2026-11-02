using Softly.Core;
using Xunit;
using A = Softly.Core.GestureAction;
using E = Softly.Core.GestureEvent;
using S = Softly.Core.RecorderState;

// Same cases as the Mac DictationCoreTests and the Linux test-controller.cjs.
public class GestureControllerTests
{
    private static void Eq(IEnumerable<GestureAction> expected, List<GestureAction> actual) =>
        Assert.Equal(expected.ToArray(), actual.ToArray());

    [Fact]
    public void HoldRepeatAndRelease()
    {
        var c = new GestureController();
        Eq(new[] { A.Start }, c.Send(E.Press, 0, S.Idle));
        Eq(Array.Empty<GestureAction>(), c.Send(E.Press, 0.1, S.Recording));
        Eq(new[] { A.Stop }, c.Send(E.Release, 1, S.Recording));
    }

    [Fact]
    public void TapLatchesThenTapFinishes()
    {
        var c = new GestureController();
        Eq(new[] { A.Start }, c.Send(E.Press, 0, S.Idle));
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 0.08, S.Recording));
        Assert.True(c.Locked);
        Eq(new[] { A.Stop }, c.Send(E.Press, 2, S.Recording));
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 2.1, S.Transcribing));
    }

    [Fact]
    public void HoldOnlyFinishesOnAnyRelease()
    {
        var c = new GestureController { TapToStart = false };
        Eq(new[] { A.Start }, c.Send(E.Press, 0, S.Idle));
        Eq(new[] { A.Stop }, c.Send(E.Release, 0.08, S.Recording));
        Assert.False(c.Locked);
    }

    [Fact]
    public void SlowTapStillLatches()
    {
        var c = new GestureController();
        c.Send(E.Press, 0, S.Idle);
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 0.45, S.Recording));
        Assert.True(c.Locked);
    }

    [Fact]
    public void ResetWhileHeldIgnoresRelease()
    {
        var c = new GestureController();
        c.Send(E.Press, 0, S.Idle);
        c.Send(E.Reset, 0.1, S.Transcribing);
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 1, S.Idle));
    }

    [Fact]
    public void Busy()
    {
        var c = new GestureController();
        Eq(Array.Empty<GestureAction>(), c.Send(E.Press, 0, S.Transcribing));
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 0.08, S.Transcribing));
    }

    [Fact]
    public void ExternalRecordingIsStopped()
    {
        var c = new GestureController();
        Eq(new[] { A.Stop }, c.Send(E.Press, 0, S.Recording));
        Eq(Array.Empty<GestureAction>(), c.Send(E.Release, 0.08, S.Idle));
    }

    [Fact]
    public void ToggleLatches()
    {
        var c = new GestureController();
        Eq(new[] { A.Start }, c.Send(E.Toggle, 0, S.Idle));
        Assert.True(c.Locked);
        Eq(new[] { A.Stop }, c.Send(E.Toggle, 1, S.Recording));
    }

    [Fact]
    public void CancelClears()
    {
        var c = new GestureController();
        c.Send(E.Press, 0, S.Idle);
        c.Send(E.Release, 0.08, S.Recording);
        Eq(new[] { A.Cancel }, c.Send(E.Cancel, 0.1, S.Recording));
        Eq(new[] { A.Start }, c.Send(E.Press, 1, S.Idle));
    }
}

public class MotionTests
{
    [Fact]
    public void BezierEndpointsAndMonotonic()
    {
        foreach (var curve in new[] { Curve.OutCubic, Curve.InCubic, Curve.InOutCubic, Curve.InOutQuad, Curve.Morph })
        {
            Assert.Equal(0, curve.Evaluate(0), 9);
            Assert.Equal(1, curve.Evaluate(1), 9);
            double last = 0;
            for (int i = 1; i <= 100; i++)
            {
                double y = curve.Evaluate(i / 100.0);
                Assert.True(y >= last - 1e-6);
                last = y;
            }
        }
        Assert.True(Curve.OutCubic.Evaluate(0.3) > 0.5, "ease-out front-loads");
        Assert.True(Curve.InCubic.Evaluate(0.3) < 0.1, "ease-in back-loads");
    }

    [Fact]
    public void TweenRetargetsFromCurrentValue()
    {
        var t = new Tween(0);
        t.Animate(1, 0.2, Curve.OutCubic, 0);
        double mid = t.ValueAt(0.1);
        Assert.True(mid > 0 && mid < 1);
        t.Animate(0, 0.2, Curve.InCubic, 0.1);
        Assert.Equal(mid, t.ValueAt(0.1), 9);
        Assert.Equal(0, t.ValueAt(0.31), 9);
        Assert.False(t.IsAnimating(0.31));
    }

    [Fact]
    public void DelayHoldsStartValue()
    {
        var t = new Tween(0);
        t.Animate(1, 0.18, Curve.OutCubic, 0, delay: 0.04);
        Assert.Equal(0, t.ValueAt(0.03));
        Assert.Equal(1, t.ValueAt(0.23));
    }

    [Fact]
    public void Snap()
    {
        var t = new Tween(1);
        t.Animate(0, 1, Curve.InOutCubic, 0);
        t.Snap(0.5);
        Assert.Equal(0.5, t.ValueAt(0.1));
    }

    [Fact]
    public void GlyphMorphsAndSnaps()
    {
        var g = new GlyphMotion();
        g.Set(GlyphShape.More, false, 0);
        Assert.Equal(2.5, g.LinesAt(0)[0].X1);
        g.Set(GlyphShape.Check, true, 1);
        var end = g.LinesAt(1.5);
        Assert.Equal(11.5, end[1].X2, 9);
        Assert.Equal(0, end[2].Ink, 9);
        Assert.Equal(1.5, g.StrokeAt(1.5), 9);
        var mid = g.LinesAt(1.05);
        Assert.True(mid[1].X2 > 7 && mid[1].X2 < 11.5);
    }
}

public class WaveformAndTranscriptTests
{
    [Fact]
    public void WaveformShiftsNewestFirstAndSilencesWhileTranscribing()
    {
        var w = new Waveform();
        w.Tick(0.04, false, 1);
        Assert.True(w.Levels[0] > 0);
        w.Tick(0.04, true, 1);
        Assert.Equal(0, w.Levels[0]);
        Assert.True(w.Levels[1] > 0);
        for (int i = 0; i < 60; i++) w.Frame(1.0 / 60);
        Assert.Equal(w.Levels[1], w.Shown[1], 3);
    }

    [Fact]
    public void TranscriptCleanup()
    {
        Assert.Null(Transcript.Clean(new[] { " [BLANK_AUDIO]", "(silence) " }));
        Assert.Equal("Hello there. How are you?", Transcript.Clean(new[] { " Hello there.", " How are you? " }));
        Assert.Equal("Okay then", Transcript.Clean(new[] { "[Music] Okay  then" }));
        Assert.Null(Transcript.Clean(new[] { " Thanks for watching!" }));
        Assert.Null(Transcript.Clean(new[] { " Thank you for watching.", " " }));
        Assert.Null(Transcript.Clean(new[] { " you" }));
        Assert.Equal("Thanks for watching the kids tonight.", Transcript.Clean(new[] { " Thanks for watching the kids tonight." }));
    }

    [Fact]
    public void Padding()
    {
        Assert.Equal(17_600, Transcript.Padded(new float[] { 0.1f, 0.2f }).Length);
        Assert.Equal(20_000, Transcript.Padded(new float[20_000]).Length);
    }
}

// Same cases as ReplacementTests in Tests/DictationCoreTests.
public class ReplacementTests
{
    private static readonly Replacement[] Rules =
    {
        new("cloud code", "Claude Code"),
        new("cloud", "Claude"),
        new("get hub", "GitHub"),
        new("omarch", "Omarchy"),
        new("um", ""),
        new("uh", ""),
    };

    private static string Apply(string text) => Replacements.Apply(text, Rules);

    [Fact]
    public void PhrasesIgnoreCaseAndPreferTheLongestRule()
    {
        Assert.Equal("Open Claude Code and push to GitHub.", Apply("Open cloud code and push to Get Hub."));
        Assert.Equal("Ask Claude.", Apply("Ask cloud."));
        Assert.Equal("Claude Code", Apply("Cloud-code"));
        Assert.Equal("Claude Code", Apply("cloud   code"));
    }

    [Fact]
    public void OnlyWholeWordsMatch()
    {
        Assert.Equal("Omarchy runs on omarchy.", Apply("Omarch runs on omarchy."));
        Assert.Equal("Cloudy and humid.", Apply("Cloudy and humid."));
    }

    [Fact]
    public void ReplacementsAreNotReplacedAgain()
    {
        Assert.Equal("b a", Replacements.Apply("a b", new[] { new Replacement("a", "b"), new Replacement("b", "a") }));
    }

    [Fact]
    public void EmptyTargetDeletesAndTidies()
    {
        Assert.Equal("So, I think it, works.", Apply("So, um, I think it, uh, works."));
        Assert.Equal("I think so.", Apply("Um, I think so."));
        Assert.Equal("Yes.", Apply("Yes um."));
        Assert.Equal("", Apply("Um."));
        Assert.Equal("Push it to GitHub. I think it works.", Apply("Push it to get hub. Um, I think it works."));
        Assert.Equal("Done. So we ship.", Apply("Done. Uh, so we ship."));
    }

    [Fact]
    public void NoRulesLeavesTextAlone()
    {
        Assert.Equal("  Untouched ,  text ", Replacements.Apply("  Untouched ,  text ", Array.Empty<Replacement>()));
        Assert.Equal("Fine", Replacements.Apply("Fine", new[] { new Replacement("  ", "x") }));
    }
}

// Same cases as SubmitWordTests in Tests/DictationCoreTests and Linux/tests.
public class SubmitWordTests
{
    [Fact]
    public void TrailingSubmitIsStripped()
    {
        Assert.Equal(("Fix the failing test", true), SubmitWord.Split("Fix the failing test, submit."));
        Assert.Equal(("Run it", true), SubmitWord.Split("Run it. Submit!"));
        Assert.Equal(("", true), SubmitWord.Split("Submit."));
    }

    [Fact]
    public void OtherSubmitsAreKept()
    {
        Assert.Equal(("Please resubmit", false), SubmitWord.Split("Please resubmit"));
        Assert.Equal(("Submit the form tomorrow.", false), SubmitWord.Split("Submit the form tomorrow."));
    }
}
