import AppKit
import SwiftUI

/// Minimal RGBA colour with the Qt helpers the Linux pill used
/// (`Qt.darker`, `Qt.lighter`, `Qt.tint`, `Qt.alpha`).
struct RGBA {
    var r, g, b, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func alpha(_ value: Double) -> RGBA { RGBA(r, g, b, value) }

    /// HSV value divided by `factor` (Qt.darker).
    func darker(_ factor: Double) -> RGBA { scaledValue(1 / factor) }
    /// HSV value multiplied by `factor` (Qt.lighter).
    func lighter(_ factor: Double) -> RGBA { scaledValue(factor) }

    /// `overlay` composited over self (Qt.tint).
    func tint(_ overlay: RGBA) -> RGBA {
        let k = overlay.a
        return RGBA(r + (overlay.r - r) * k, g + (overlay.g - g) * k, b + (overlay.b - b) * k, a)
    }

    private func scaledValue(_ factor: Double) -> RGBA {
        let maxC = max(r, g, b)
        guard maxC > 0 else {
            // Qt lightens pure black by raising value from zero.
            let v = min(1, factor > 1 ? (factor - 1) * 0.1 : 0)
            return RGBA(v, v, v, a)
        }
        let target = min(1, maxC * factor)
        let k = target / maxC
        return RGBA(r * k, g * k, b * k, a)
    }
}

/// Dark capsule with the system accent colour for the backlight, so it
/// follows macOS the way the Linux pill follows the Omarchy theme.
struct Palette {
    var background = RGBA(hex: 0x12151C)
    var foreground = RGBA(hex: 0xE6E8EE)
    var accent = RGBA(NSColor.controlAccentColor)

    var floor: RGBA { background.darker(1.5) }

    static var current: Palette { Palette() }
}
