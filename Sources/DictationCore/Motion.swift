import Foundation

/// CSS-style cubic Bézier timing curve, solved for y given x (time fraction).
public struct CubicBezier: Sendable {
    private let cx, bx, ax, cy, by, ay: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    public func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-6 { return sampleY(t) }
            let d = slopeX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while hi - lo > 1e-6 {
            let v = sampleX(t)
            if abs(v - x) < 1e-6 { break }
            if x > v { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sampleY(t)
    }
}

/// The curves used by the Linux pill (Qt easing equivalents).
public enum Curve {
    public static let outCubic = CubicBezier(0.33, 1, 0.68, 1)
    public static let inCubic = CubicBezier(0.32, 0, 0.67, 0)
    public static let inOutCubic = CubicBezier(0.65, 0, 0.35, 1)
    public static let inOutQuad = CubicBezier(0.45, 0, 0.55, 1)
    /// Exponential ease-out recommended by the morphing-icons skill.
    public static let morph = CubicBezier(0.19, 1, 0.22, 1)
}

/// A value that eases toward a target, like a Qt `Behavior`/`NumberAnimation`.
/// Retargeting starts from the current value, so interruptions never jump.
public struct Tween: Sendable {
    public private(set) var target: Double
    private var from: Double
    private var start: Double = 0
    private var delay: Double = 0
    private var duration: Double = 0
    private var curve = Curve.outCubic

    public init(_ value: Double) { target = value; from = value }

    public func value(at now: Double) -> Double {
        guard duration > 0 else { return target }
        let x = (now - start - delay) / duration
        if x <= 0 { return from }
        if x >= 1 { return target }
        return from + (target - from) * curve(x)
    }

    public func isAnimating(at now: Double) -> Bool {
        duration > 0 && now < start + delay + duration
    }

    public mutating func animate(to value: Double, duration: Double, curve: CubicBezier, delay: Double = 0, now: Double) {
        let current = self.value(at: now)
        if value == target && !isAnimating(at: now) { return }
        from = current
        target = value
        start = now
        self.delay = delay
        self.duration = duration
        self.curve = curve
    }

    /// Jump immediately (used while the pill is hidden).
    public mutating func snap(to value: Double) {
        target = value; from = value; duration = 0
    }

    /// Animate when visible, snap when hidden.
    public mutating func set(_ value: Double, animated: Bool, duration: Double, curve: CubicBezier, now: Double) {
        if animated { animate(to: value, duration: duration, curve: curve, now: now) } else { snap(to: value) }
    }
}

public func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

/// Smoothstep between `a` and `b`.
public func ramp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    let x = clamp01((t - a) / (b - a))
    return x * x * (3 - 2 * x)
}
