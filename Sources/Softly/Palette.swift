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

/// One pill style: capsule, ink and backlight colours. Light capsules use
/// softer shadows and a shallower groove, as the Linux pill does under a
/// light Omarchy theme. The same table lives in Windows/Softly/Palette.cs
/// and Linux/plugin/Themes.js; keep the three in step.
struct PillTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: UInt32
    let foreground: UInt32
    /// nil follows the macOS accent colour.
    let accent: UInt32?

    static let all: [PillTheme] = [
        PillTheme(id: "system", name: "Midnight", background: 0x12151C, foreground: 0xE6E8EE, accent: nil),
        PillTheme(id: "graphite", name: "Graphite", background: 0x1C1D20, foreground: 0xEDEDED, accent: 0xD9DCE3),
        PillTheme(id: "ember", name: "Ember", background: 0x1F1612, foreground: 0xF5E7DD, accent: 0xFF7A3D),
        PillTheme(id: "forest", name: "Forest", background: 0x101A14, foreground: 0xDCEBE0, accent: 0x4ADE80),
        PillTheme(id: "lagoon", name: "Lagoon", background: 0x0D1A20, foreground: 0xDCF1F5, accent: 0x2DD4BF),
        PillTheme(id: "rose", name: "Rose", background: 0x1F1318, foreground: 0xF7E4EB, accent: 0xFF5C8A),
        PillTheme(id: "violet", name: "Violet", background: 0x19112B, foreground: 0xEFE6FF, accent: 0xB57BFF),
        PillTheme(id: "brass", name: "Brass", background: 0x18150E, foreground: 0xF2EAD5, accent: 0xF2C14E),
        PillTheme(id: "paper", name: "Paper", background: 0xF3EFE6, foreground: 0x2B2722, accent: 0xE0703A),
        PillTheme(id: "frost", name: "Frost", background: 0xEDF1F6, foreground: 0x1D2633, accent: 0x2F7CF6),
        PillTheme(id: "blush", name: "Blush", background: 0xF7EAEC, foreground: 0x3B242A, accent: 0xE04F78),
    ]

    static func named(_ id: String) -> PillTheme { all.first { $0.id == id } ?? all[0] }

    var palette: Palette {
        Palette(background: RGBA(hex: background), foreground: RGBA(hex: foreground),
                accent: accent.map { RGBA(hex: $0) } ?? RGBA(NSColor.controlAccentColor))
    }
}

/// The chosen style's colours. Midnight, the default, takes the system accent
/// for the backlight, so it follows macOS the way the Linux pill follows the
/// Omarchy theme.
struct Palette {
    var background: RGBA
    var foreground: RGBA
    var accent: RGBA

    /// HSL lightness above one half, as Service.qml's lightTheme.
    var isLight: Bool {
        let hi = max(background.r, background.g, background.b)
        let lo = min(background.r, background.g, background.b)
        return (hi + lo) / 2 > 0.5
    }

    var floor: RGBA { isLight ? background.darker(1.12) : background.darker(1.5) }

    static var current: Palette { PillTheme.named(Settings.pillTheme).palette }
}
