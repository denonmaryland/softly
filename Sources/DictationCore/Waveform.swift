import Foundation

/// RMS-driven bars, same shaping as the Linux pill. Visualization only;
/// never changes capture gain.
public struct Waveform: Sendable {
    public static let barCount = 19
    public static let tickInterval = 0.040

    public private(set) var envelope: Double = 0
    public private(set) var levels = [Double](repeating: 0, count: barCount)
    public private(set) var shown = [Double](repeating: 0, count: barCount)

    public init() {}

    public mutating func reset() { self = Waveform() }

    /// Every 40 ms: compress and smooth the level, push the newest bar in.
    public mutating func tick(rms: Double, transcribing: Bool, jitter: Double) {
        let target = min(1, (max(0, rms)).squareRoot() * 2.2)
        envelope += (target - envelope) * (target > envelope ? 0.5 : 0.2)
        let live = transcribing ? 0 : envelope * (0.55 + 0.45 * jitter)
        levels = [live] + levels.dropLast()
    }

    /// Every frame: ease displayed bars toward their levels.
    public mutating func frame(dt: Double) {
        let k = 1 - exp(-dt * 22)
        for i in shown.indices { shown[i] += (levels[i] - shown[i]) * k }
    }
}

/// Root-mean-square of a buffer of samples.
public func rootMeanSquare(_ samples: UnsafeBufferPointer<Float>) -> Double {
    guard !samples.isEmpty else { return 0 }
    var sum: Double = 0
    for s in samples { sum += Double(s) * Double(s) }
    return (sum / Double(samples.count)).squareRoot()
}
