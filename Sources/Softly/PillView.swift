import DictationCore
import SwiftUI

/// Draws the backlit-groove capsule each frame. Layer order, sizes and
/// formulas follow the Linux Service.qml so the two look the same.
struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !model.onScreen)) { _ in
            let frame = model.nextFrame()
            Canvas { context, _ in
                PillRenderer(frame: frame, palette: .current).draw(in: &context)
            }
        }
        .frame(width: PillGeometry.panelSize.width, height: PillGeometry.panelSize.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { model.pointerDown(at: value.startLocation) }
                }
                .onEnded { value in model.pointerUp(at: value.location, startedAt: value.startLocation) }
        )
    }
}

/// Everything one frame needs, sampled on the main thread.
struct PillFrame {
    var presence, surface, content, processing, completion, glow, hover, pressScale: Double
    var envelope, phase: Double
    var shown: [Double]
    var timerText: String
    var glyphLines: [GlyphLine]
    var glyphStroke: Double
}

struct PillRenderer {
    let frame: PillFrame
    let palette: Palette

    private var presence: Double { frame.presence }
    private var surface: Double { frame.surface }
    private var content: Double { frame.content }
    private var processing: Double { frame.processing }
    private var completion: Double { frame.completion }
    private var glow: Double { frame.glow }
    private var hover: Double { frame.hover }

    private func capsule(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2)
    }

    func draw(in context: inout GraphicsContext) {
        let p = presence
        let size = PillGeometry.panelSize
        var ctx = context
        // The whole surface is composited once, then faded, lifted and scaled.
        ctx.opacity = surface
        ctx.translateBy(x: size.width / 2, y: size.height / 2 + 4 * (1 - p))
        ctx.scaleBy(x: 0.96 + 0.04 * p, y: 0.96 + 0.04 * p)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        ctx.drawLayer { layer in
            layer.translateBy(x: PillGeometry.pebble.minX, y: PillGeometry.pebble.minY)
            drawPebble(in: &layer)
            drawGroove(in: &layer)
            drawClock(in: &layer)
        }
    }

    // MARK: Capsule

    private func drawPebble(in ctx: inout GraphicsContext) {
        let w = PillGeometry.pebble.width, h = PillGeometry.pebble.height
        let bg = palette.background
        let full = CGRect(x: 0, y: 0, width: w, height: h)

        // Lifted: a soft ambient shadow (spread −5) and a tight contact shadow.
        // The casters sit inside the opaque capsule drawn over them.
        var ambient = ctx
        ambient.addFilter(.shadow(color: .black.opacity(0.6), radius: 7.5, x: 0, y: 7))
        ambient.fill(capsule(full.insetBy(dx: 5, dy: 5)), with: .color(.black))
        var contact = ctx
        contact.addFilter(.shadow(color: .black.opacity(0.4), radius: 0.75, x: 0, y: 1))
        contact.fill(capsule(full.insetBy(dx: 1, dy: 1)), with: .color(.black))

        ctx.fill(capsule(full.insetBy(dx: -1, dy: -1)), with: .color(RGBA(0, 0, 0, 0.55).color))
        // Lit chamfer: dark lower lip and lit upper lip peek out around the face.
        ctx.fill(capsule(full), with: .color(bg.darker(1.1).tint(RGBA(0, 0, 0, 0.45)).color))
        ctx.fill(capsule(CGRect(x: 0, y: 0, width: w, height: h - 1)),
                 with: .color(bg.lighter(1.13).tint(RGBA(1, 0.98, 0.92, 0.18)).color))
        let face = CGRect(x: 0, y: 1, width: w, height: h - 2)
        ctx.fill(capsule(face), with: .linearGradient(
            Gradient(stops: [
                .init(color: bg.lighter(1.13).color, location: 0),
                .init(color: bg.color, location: 0.5),
                .init(color: bg.darker(1.1).color, location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY)
        ))
    }

    // MARK: Groove and waveform

    private func drawGroove(in context: inout GraphicsContext) {
        let g = PillGeometry.groove
        let floor = palette.floor
        let accent = palette.accent
        let c = completion, pr = processing, cp = content
        var ctx = context
        ctx.opacity *= cp
        ctx.translateBy(x: g.minX, y: g.minY)
        ctx.drawLayer { layer in
            let full = CGRect(x: 0, y: 0, width: g.width, height: g.height)
            // Lower lip catches the backlight; the upper edge falls into shadow.
            layer.fill(capsule(full), with: .color(floor.tint(accent.alpha(0.12 + 0.1 * glow)).color))
            layer.fill(capsule(CGRect(x: 0, y: 0, width: g.width, height: g.height - 1)),
                       with: .color(floor.darker(1.6).color))
            let floorRect = CGRect(x: 0, y: 1.25, width: g.width, height: g.height - 2.25)
            layer.fill(capsule(floorRect), with: .color(floor.color))

            // Backlight, blooming from the centre as the content arrives.
            var light = layer
            light.opacity *= glow * (0.82 + 0.18 * frame.envelope)
            light.translateBy(x: g.width / 2, y: 0)
            light.scaleBy(x: 0.55 + 0.45 * cp, y: 1)
            light.translateBy(x: -g.width / 2, y: 0)
            light.fill(capsule(floorRect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: accent.alpha(0).color, location: 0),
                    .init(color: accent.alpha(0.08).color, location: 0.22),
                    .init(color: accent.alpha(0.3).color, location: 0.5),
                    .init(color: accent.alpha(0.08).color, location: 0.78),
                    .init(color: accent.alpha(0).color, location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: g.width, y: 0)
            ))

            // Inner shadow under the top edge keeps the glow low in the cut.
            layer.fill(capsule(floorRect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: floor.darker(1.4).alpha(0.8).color, location: 0),
                    .init(color: floor.alpha(0).color, location: 0.45),
                ]),
                startPoint: CGPoint(x: 0, y: floorRect.minY), endPoint: CGPoint(x: 0, y: floorRect.maxY)
            ))

            let shown = frame.shown
            for i in 0..<Waveform.barCount {
                let fromCentre = abs(Double(i) - 9) / 9
                let taper = 1 - 0.65 * fromCentre
                // Centre-out reveal: the outermost bar trails by ~60 ms.
                let reveal = clamp01((cp - 0.35 * fromCentre) / 0.65)
                let live = shown[i] * taper
                let busy = 0.15 + 0.32 * (0.5 + 0.5 * sin(frame.phase * 6 - Double(i) * 0.55))
                let activity = (live * (1 - pr) + busy * pr) * (1 - c)
                let home = 8 + Double(i) * 4.917
                // On completion the waveform gathers into the centre dot.
                let x = home + (52.25 - home) * c
                let height = 2.5 + min(1, activity) * 13
                let alpha = (0.95 - 0.25 * pr) * reveal * (1 - ramp(0.35, 0.9, c))
                guard alpha > 0.001 else { continue }
                var bar = layer
                bar.opacity *= alpha
                bar.fill(Path(roundedRect: CGRect(x: x, y: (g.height - height) / 2, width: 2.5, height: height),
                              cornerRadius: 1.25),
                         with: .color(palette.foreground.color))
            }

            let dotAlpha = ramp(0.3, 0.85, c)
            if dotAlpha > 0.001 {
                let d = 5 * (0.5 + 0.5 * c)
                var dot = layer
                dot.opacity *= dotAlpha
                dot.fill(Path(ellipseIn: CGRect(x: g.width / 2 - d / 2, y: g.height / 2 - d / 2, width: d, height: d)),
                         with: .color(palette.foreground.color))
            }
        }
    }

    // MARK: Timer, glyph, cancel target

    private func drawClock(in context: inout GraphicsContext) {
        let area = CGRect(x: 112, y: 0, width: 41, height: PillGeometry.pebble.height)
        let center = CGPoint(x: area.midX, y: area.midY)
        let scale = frame.pressScale
        let timerMix = (1 - processing) * (1 - completion) * (1 - hover)

        var ctx = context
        ctx.opacity *= content
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: scale, y: scale)

        // The timer clears before the glyph shows, so text and icon never overlap.
        if timerMix > 0.001 {
            var timer = ctx
            timer.opacity *= timerMix * timerMix
            timer.draw(
                Text(frame.timerText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(palette.foreground.alpha(0.76).color),
                at: .zero, anchor: .center
            )
        }

        let glyphAlpha = (0.76 + 0.24 * hover) * clamp01(1 - 2.5 * timerMix)
        guard glyphAlpha > 0.001 else { return }
        var glyph = ctx
        glyph.opacity *= glyphAlpha
        let unit = 0.8
        let stroke = frame.glyphStroke
        // Composited once so the check's overlapping caps keep even ink.
        glyph.drawLayer { layer in
            layer.translateBy(x: -7 * unit, y: -7 * unit)
            for line in frame.glyphLines where line.ink > 0.001 {
                var ink = layer
                ink.opacity *= line.ink
                let a = CGPoint(x: line.x1 * unit, y: line.y1 * unit)
                let b = CGPoint(x: line.x2 * unit, y: line.y2 * unit)
                if hypot(b.x - a.x, b.y - a.y) < 0.01 {
                    ink.fill(Path(ellipseIn: CGRect(x: a.x - stroke / 2, y: a.y - stroke / 2, width: stroke, height: stroke)),
                             with: .color(palette.foreground.color))
                } else {
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    ink.stroke(path, with: .color(palette.foreground.color),
                               style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
            }
        }
    }
}
