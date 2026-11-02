import XCTest
@testable import DictationCore

final class GestureControllerTests: XCTestCase {
    // Same cases as the Linux plugin's test-controller.cjs (times in seconds).
    func testHoldRepeatAndRelease() {
        var c = GestureController()
        XCTAssertEqual(c.send(.press, now: 0, state: .idle), [.start])
        XCTAssertEqual(c.send(.press, now: 0.1, state: .recording), [], "repeats ignored")
        XCTAssertEqual(c.send(.release, now: 1, state: .recording), [.stop])
    }

    func testTapLatchesThenTapFinishes() {
        var c = GestureController()
        XCTAssertEqual(c.send(.press, now: 0, state: .idle), [.start])
        XCTAssertEqual(c.send(.release, now: 0.08, state: .recording), [])
        XCTAssertTrue(c.locked)
        XCTAssertEqual(c.send(.press, now: 2, state: .recording), [.stop])
        XCTAssertEqual(c.send(.release, now: 2.1, state: .transcribing), [])
    }

    func testSlowTapStillLatches() {
        var c = GestureController()
        _ = c.send(.press, now: 0, state: .idle)
        XCTAssertEqual(c.send(.release, now: 0.45, state: .recording), [])
        XCTAssertTrue(c.locked)
    }

    func testHoldOnlyFinishesOnAnyRelease() {
        var c = GestureController()
        c.tapToStart = false
        XCTAssertEqual(c.send(.press, now: 0, state: .idle), [.start])
        XCTAssertEqual(c.send(.release, now: 0.08, state: .recording), [.stop])
        XCTAssertFalse(c.locked)
    }

    func testResetWhileHeldIgnoresRelease() {
        var c = GestureController()
        _ = c.send(.press, now: 0, state: .idle)
        _ = c.send(.reset, now: 0.1, state: .transcribing)
        XCTAssertEqual(c.send(.release, now: 1, state: .idle), [], "cap reached while held")
    }

    func testBusy() {
        var c = GestureController()
        XCTAssertEqual(c.send(.press, now: 0, state: .transcribing), [])
        XCTAssertEqual(c.send(.release, now: 0.08, state: .transcribing), [])
    }

    func testExternalRecordingIsStopped() {
        var c = GestureController()
        XCTAssertEqual(c.send(.press, now: 0, state: .recording), [.stop])
        XCTAssertEqual(c.send(.release, now: 0.08, state: .idle), [])
    }

    func testToggle() {
        var c = GestureController()
        XCTAssertEqual(c.send(.toggle, now: 0, state: .idle), [.start])
        XCTAssertTrue(c.locked)
        XCTAssertEqual(c.send(.toggle, now: 1, state: .recording), [.stop])
    }

    func testCancel() {
        var c = GestureController()
        _ = c.send(.press, now: 0, state: .idle)
        _ = c.send(.release, now: 0.08, state: .recording)
        XCTAssertEqual(c.send(.cancel, now: 0.1, state: .recording), [.cancel])
        XCTAssertEqual(c.send(.press, now: 1, state: .idle), [.start], "a fresh start after cancel")
    }
}

final class MotionTests: XCTestCase {
    func testBezierEndpointsAndMonotonic() {
        for curve in [Curve.outCubic, Curve.inCubic, Curve.inOutCubic, Curve.inOutQuad, Curve.morph] {
            XCTAssertEqual(curve(0), 0, accuracy: 1e-9)
            XCTAssertEqual(curve(1), 1, accuracy: 1e-9)
            var last = 0.0
            for i in 1...100 {
                let y = curve(Double(i) / 100)
                XCTAssertGreaterThanOrEqual(y, last - 1e-6)
                last = y
            }
        }
        XCTAssertGreaterThan(Curve.outCubic(0.3), 0.5, "ease-out front-loads")
        XCTAssertLessThan(Curve.inCubic(0.3), 0.1, "ease-in back-loads")
    }

    func testTweenRetargetsFromCurrentValue() {
        var t = Tween(0)
        t.animate(to: 1, duration: 0.2, curve: Curve.outCubic, now: 0)
        let mid = t.value(at: 0.1)
        XCTAssertTrue(mid > 0 && mid < 1)
        t.animate(to: 0, duration: 0.2, curve: Curve.inCubic, now: 0.1)
        XCTAssertEqual(t.value(at: 0.1), mid, accuracy: 1e-9, "no jump on interruption")
        XCTAssertEqual(t.value(at: 0.31), 0, accuracy: 1e-9)
        XCTAssertFalse(t.isAnimating(at: 0.31))
    }

    func testDelayHoldsStartValue() {
        var t = Tween(0)
        t.animate(to: 1, duration: 0.18, curve: Curve.outCubic, delay: 0.04, now: 0)
        XCTAssertEqual(t.value(at: 0.03), 0)
        XCTAssertEqual(t.value(at: 0.23), 1)
    }

    func testSnap() {
        var t = Tween(1)
        t.animate(to: 0, duration: 1, curve: Curve.inOutCubic, now: 0)
        t.snap(to: 0.5)
        XCTAssertEqual(t.value(at: 0.1), 0.5)
    }

    func testGlyphMorphsAndSnaps() {
        var g = GlyphMotion()
        g.set(.more, animated: false, now: 0)
        XCTAssertEqual(g.lines(at: 0)[0].x1, 2.5)
        g.set(.check, animated: true, now: 1)
        let end = g.lines(at: 1.5)
        XCTAssertEqual(end[1].x2, 11.5, accuracy: 1e-9)
        XCTAssertEqual(end[2].ink, 0, accuracy: 1e-9)
        XCTAssertEqual(g.stroke(at: 1.5), 1.5, accuracy: 1e-9)
        let mid = g.lines(at: 1.05)
        XCTAssertTrue(mid[1].x2 > 7 && mid[1].x2 < 11.5)
    }
}

final class WaveformAndTranscriptTests: XCTestCase {
    func testWaveformShiftsNewestFirstAndSilencesWhileTranscribing() {
        var w = Waveform()
        w.tick(rms: 0.04, transcribing: false, jitter: 1)
        XCTAssertGreaterThan(w.levels[0], 0)
        w.tick(rms: 0.04, transcribing: true, jitter: 1)
        XCTAssertEqual(w.levels[0], 0)
        XCTAssertGreaterThan(w.levels[1], 0)
        for _ in 0..<60 { w.frame(dt: 1.0 / 60) }
        XCTAssertEqual(w.shown[1], w.levels[1], accuracy: 1e-3)
    }

    func testTranscriptCleanup() {
        XCTAssertNil(Transcript.clean([" [BLANK_AUDIO]", "(silence) "]))
        XCTAssertEqual(Transcript.clean([" Hello there.", " How are you? "]), "Hello there. How are you?")
        XCTAssertEqual(Transcript.clean(["[Music] Okay  then"]), "Okay then")
        XCTAssertNil(Transcript.clean([" Thanks for watching!"]))
        XCTAssertNil(Transcript.clean([" Thank you for watching.", " "]))
        XCTAssertNil(Transcript.clean([" you"]))
        XCTAssertEqual(Transcript.clean([" Thanks for watching the kids tonight."]), "Thanks for watching the kids tonight.")
    }

    func testPadding() {
        XCTAssertEqual(Transcript.padded([0.1, 0.2]).count, 17_600)
        XCTAssertEqual(Transcript.padded([Float](repeating: 0, count: 20_000)).count, 20_000)
    }
}

// Same cases as ReplacementTests in Windows/Softly.Core.Tests.
final class ReplacementTests: XCTestCase {
    private let rules = [
        Replacement(from: "cloud code", to: "Claude Code"),
        Replacement(from: "cloud", to: "Claude"),
        Replacement(from: "get hub", to: "GitHub"),
        Replacement(from: "omarch", to: "Omarchy"),
        Replacement(from: "um", to: ""),
        Replacement(from: "uh", to: ""),
    ]

    private func apply(_ text: String) -> String { Replacements.apply(text, rules) }

    func testPhrasesIgnoreCaseAndPreferTheLongestRule() {
        XCTAssertEqual(apply("Open cloud code and push to Get Hub."), "Open Claude Code and push to GitHub.")
        XCTAssertEqual(apply("Ask cloud."), "Ask Claude.")
        XCTAssertEqual(apply("Cloud-code"), "Claude Code")
        XCTAssertEqual(apply("cloud   code"), "Claude Code")
    }

    func testOnlyWholeWordsMatch() {
        XCTAssertEqual(apply("Omarch runs on omarchy."), "Omarchy runs on omarchy.")
        XCTAssertEqual(apply("Cloudy and humid."), "Cloudy and humid.")
    }

    func testReplacementsAreNotReplacedAgain() {
        XCTAssertEqual(Replacements.apply("a b", [Replacement(from: "a", to: "b"), Replacement(from: "b", to: "a")]), "b a")
    }

    func testEmptyTargetDeletesAndTidies() {
        XCTAssertEqual(apply("So, um, I think it, uh, works."), "So, I think it, works.")
        XCTAssertEqual(apply("Um, I think so."), "I think so.")
        XCTAssertEqual(apply("Yes um."), "Yes.")
        XCTAssertEqual(apply("Um."), "")
        XCTAssertEqual(apply("Push it to get hub. Um, I think it works."), "Push it to GitHub. I think it works.")
        XCTAssertEqual(apply("Done. Uh, so we ship."), "Done. So we ship.")
    }

    func testNoRulesLeavesTextAlone() {
        XCTAssertEqual(Replacements.apply("  Untouched ,  text ", []), "  Untouched ,  text ")
        XCTAssertEqual(Replacements.apply("Fine", [Replacement(from: "  ", to: "x")]), "Fine")
    }
}

// Same cases as SubmitWordTests in Windows/Softly.Core.Tests and Linux/tests.
final class SubmitWordTests: XCTestCase {
    func testTrailingSubmitIsStripped() {
        XCTAssertEqual(SubmitWord.split("Fix the failing test, submit.").text, "Fix the failing test")
        XCTAssertTrue(SubmitWord.split("Fix the failing test, submit.").submit)
        XCTAssertEqual(SubmitWord.split("Run it. Submit!").text, "Run it")
        XCTAssertEqual(SubmitWord.split("Submit.").text, "")
        XCTAssertTrue(SubmitWord.split("Submit.").submit)
    }

    func testOtherSubmitsAreKept() {
        XCTAssertFalse(SubmitWord.split("Please resubmit").submit)
        XCTAssertFalse(SubmitWord.split("Submit the form tomorrow.").submit)
        XCTAssertEqual(SubmitWord.split("Submit the form tomorrow.").text, "Submit the form tomorrow.")
    }
}
