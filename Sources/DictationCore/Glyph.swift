/// Status glyph: three round-capped lines in a 14-unit box. Unused lines
/// collapse to the centre, so any shape morphs into any other.
public enum GlyphShape: Sendable, CaseIterable {
    case none, more, check, cross

    /// Each line: x1, y1, x2, y2, ink (opacity).
    public var lines: [[Double]] {
        switch self {
        case .none: return [[7, 7, 7, 7, 0], [7, 7, 7, 7, 0], [7, 7, 7, 7, 0]]
        case .more: return [[2.5, 7, 2.5, 7, 1], [7, 7, 7, 7, 1], [11.5, 7, 11.5, 7, 1]]
        case .check: return [[2.5, 7.5, 5.5, 10.5, 1], [5.5, 10.5, 11.5, 3.5, 1], [7, 7, 7, 7, 0]]
        // The outer dots become the diagonals, so dots→× folds symmetrically.
        case .cross: return [[3, 3, 11, 11, 1], [7, 7, 7, 7, 0], [11, 3, 3, 11, 1]]
        }
    }

    public var stroke: Double { self == .more ? 2.5 : 1.5 }
}

public struct GlyphLine: Sendable {
    public var x1, y1, x2, y2, ink: Double
}

/// Fifteen tweens (3 lines × 5 values) plus stroke width.
public struct GlyphMotion: Sendable {
    public static let duration = 0.4
    private var values: [Tween]
    private var strokeTween: Tween
    public private(set) var shape: GlyphShape = .none

    public init() {
        values = GlyphShape.none.lines.flatMap { $0 }.map { Tween($0) }
        strokeTween = Tween(GlyphShape.none.stroke)
    }

    public mutating func set(_ shape: GlyphShape, animated: Bool, now: Double) {
        guard shape != self.shape || !animated else { return }
        self.shape = shape
        for (i, v) in shape.lines.flatMap({ $0 }).enumerated() {
            values[i].set(v, animated: animated, duration: Self.duration, curve: Curve.morph, now: now)
        }
        strokeTween.set(shape.stroke, animated: animated, duration: Self.duration, curve: Curve.morph, now: now)
    }

    public func lines(at now: Double) -> [GlyphLine] {
        (0..<3).map { i in
            let v = { (k: Int) in values[i * 5 + k].value(at: now) }
            return GlyphLine(x1: v(0), y1: v(1), x2: v(2), y2: v(3), ink: v(4))
        }
    }

    public func stroke(at now: Double) -> Double { strokeTween.value(at: now) }
}
