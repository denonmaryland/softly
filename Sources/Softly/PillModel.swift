import AppKit
import DictationCore
import SwiftUI

/// Motion state for the pill, a direct port of the Linux QML behaviours.
///
/// Entrance: geometry 260 ms ease-out with 4 pt lift and 0.96→1 scale; surface
/// 160 ms; content 180 ms after 40 ms. Exit: geometry 180 ms ease-in; surface
/// and content fade evenly. State blends snap while hidden so a new session
/// never replays the last ending.
@MainActor
final class PillModel: ObservableObject {
    enum Display { case recording, transcribing, complete }

    /// Panel ordered in. Drives the frame clock; not touched every frame.
    @Published private(set) var onScreen = false

    private(set) var showing = false
    private(set) var display: Display = .recording
    private(set) var previewing = false

    var presence = Tween(0)
    var surface = Tween(0)
    var content = Tween(0)
    var processing = Tween(0)
    var completion = Tween(0)
    var glow = Tween(1)
    var hover = Tween(0)
    var pressScale = Tween(1)
    var glyph = GlyphMotion()

    private(set) var waveform = Waveform()
    private(set) var phase: Double = 0
    private(set) var elapsed = 0
    private var startedAt: Double = 0
    private var lastFrame: Double?
    private var hovering = false
    private var levelTimer: Timer?
    private var hideCheck = 0

    /// Live microphone RMS, provided by the engine.
    var levelSource: () -> Double = { 0 }
    var onCancelClick: () -> Void = {}
    var onScreenChange: (Bool) -> Void = { _ in }
    /// Pointer location in pill coordinates, or nil when outside the panel.
    var pointerLocation: () -> CGPoint? = { nil }

    static var now: Double { ProcessInfo.processInfo.systemUptime }

    var timerText: String { "\(elapsed / 60):" + String(format: "%02d", elapsed % 60) }

    private var animated: Bool { onScreen }

    // MARK: Session

    func beginSession(preview: Bool = false) {
        previewing = preview
        setDisplay(.recording)
        waveform.reset()
        startedAt = Self.now
        elapsed = 0
        show()
    }

    func setDisplay(_ next: Display) {
        display = next
        let now = Self.now
        processing.set(next == .transcribing ? 1 : 0, animated: animated, duration: 0.18, curve: Curve.inOutCubic, now: now)
        completion.set(next == .complete ? 1 : 0, animated: animated, duration: 0.18, curve: Curve.inOutCubic, now: now)
        let light: Double = next == .transcribing ? 0 : (next == .complete ? 0.55 : 1)
        glow.set(light, animated: animated, duration: 0.22, curve: Curve.inOutCubic, now: now)
        updateHover(now: now)
    }

    func show() {
        let now = Self.now
        showing = true
        hideCheck += 1
        if !onScreen {
            onScreen = true
            onScreenChange(true)
        }
        presence.animate(to: 1, duration: 0.26, curve: Curve.outCubic, now: now)
        surface.animate(to: 1, duration: 0.16, curve: Curve.outCubic, now: now)
        content.animate(to: 1, duration: 0.18, curve: Curve.outCubic, delay: 0.04, now: now)
        startLevelTimer()
    }

    func hide() {
        guard showing else { return }
        let now = Self.now
        showing = false
        previewing = false
        presence.animate(to: 0, duration: 0.18, curve: Curve.inCubic, now: now)
        surface.animate(to: 0, duration: 0.18, curve: Curve.inOutQuad, now: now)
        content.animate(to: 0, duration: 0.11, curve: Curve.inOutQuad, now: now)
        levelTimer?.invalidate()
        levelTimer = nil
        hideCheck += 1
        let token = hideCheck
        after(0.25) { [weak self] in
            guard let self, token == self.hideCheck, !self.showing else { return }
            self.onScreen = false
            self.onScreenChange(false)
        }
    }

    // MARK: Clock

    private func startLevelTimer() {
        guard levelTimer == nil else { return }
        let timer = Timer(timeInterval: Waveform.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLevels() }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func tickLevels() {
        var rms = levelSource()
        if previewing {
            // Speech-like fake level so the look can be checked without the mic.
            rms = 0.004 + 0.09 * pow(abs(sin(phase * 3.1) * sin(phase * 0.7 + 0.6)), 1.2) * Double.random(in: 0...1)
        }
        waveform.tick(rms: rms, transcribing: display == .transcribing, jitter: Double.random(in: 0...1))
        if display == .recording { elapsed = Int(Self.now - startedAt) }
    }

    /// Called once per displayed frame by the view: advances the clock and
    /// samples every animated value.
    func nextFrame() -> PillFrame {
        let now = Self.now
        let dt = min(0.1, max(0, now - (lastFrame ?? now)))
        lastFrame = now
        phase += dt
        waveform.frame(dt: dt)
        updateHover(now: now)
        return PillFrame(
            presence: presence.value(at: now), surface: surface.value(at: now),
            content: content.value(at: now), processing: processing.value(at: now),
            completion: completion.value(at: now), glow: glow.value(at: now),
            hover: hover.value(at: now), pressScale: pressScale.value(at: now),
            envelope: waveform.envelope, phase: phase, shown: waveform.shown,
            timerText: timerText, glyphLines: glyph.lines(at: now), glyphStroke: glyph.stroke(at: now)
        )
    }

    // MARK: Pointer

    private func updateHover(now: Double) {
        let inside = pointerLocation().map { PillGeometry.clockRect.contains($0) } ?? false
        hovering = inside && showing && content.value(at: now) > 0.9
        let target: Double = hovering && display != .complete ? 1 : 0
        if target != hover.target {
            hover.set(target, animated: animated, duration: 0.14, curve: Curve.inOutCubic, now: now)
        }
        let shape: GlyphShape = display == .complete ? .check
            : hovering ? .cross
            : display == .transcribing ? .more : .none
        if shape != glyph.shape || !animated {
            glyph.set(shape, animated: animated, now: now)
        }
    }

    func pointerDown(at point: CGPoint) {
        guard PillGeometry.clockRect.contains(point) else { return }
        pressScale.animate(to: 0.97, duration: 0.14, curve: Curve.outCubic, now: Self.now)
    }

    func pointerUp(at point: CGPoint, startedAt start: CGPoint) {
        pressScale.animate(to: 1, duration: 0.14, curve: Curve.outCubic, now: Self.now)
        let rect = PillGeometry.clockRect
        if rect.contains(point), rect.contains(start), showing, content.value(at: Self.now) > 0.9 {
            onCancelClick()
        }
    }
}

/// Fixed geometry of the Linux pill, in points.
enum PillGeometry {
    static let panelSize = CGSize(width: 189, height: 64)
    static let pebble = CGRect(x: 18, y: 15.85, width: 153, height: 32.3)
    static let groove = CGRect(x: 5.25, y: (32.3 - 22) / 2, width: 107, height: 22)
    /// Timer / glyph / cancel target, in panel coordinates.
    static let clockRect = CGRect(x: pebble.minX + 112, y: pebble.minY, width: 41, height: pebble.height)
    /// Space between the pill and the Dock / screen edge.
    static let bottomMargin: CGFloat = 14
}
