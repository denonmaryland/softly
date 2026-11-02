import SwiftUI

/// The pill: a large preview of the chosen style and the eleven to pick from.
@MainActor
struct LookView: View {
    @ObservedObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 4, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Look", subtitle: "The pill that floats over your work while you talk.")

            VStack(spacing: 14) {
                PillSample(theme: PillTheme.named(state.pillTheme))
                CobaltLink(title: "Play preview", action: state.previewPill)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gallery.well))
            .padding(.bottom, 32)

            GallerySection(title: "Pill style", detail: "Midnight follows your Mac’s accent colour.") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(PillTheme.all) { theme in
                        let selected = theme.id == state.pillTheme
                        Button {
                            guard !selected else { return }
                            state.pillTheme = theme.id
                            state.previewPill()
                        } label: {
                            HStack(spacing: 8) {
                                StyleDot(theme: theme, selected: selected)
                                Text(theme.name)
                                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Gallery.cobalt.opacity(0.09) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.name) pill")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.top, -6)
            }
        }
    }
}

/// The style's background with its accent in the middle.
private struct StyleDot: View {
    let theme: PillTheme
    let selected: Bool

    var body: some View {
        let palette = theme.palette
        ZStack {
            Circle().fill(palette.background.color)
            Circle().stroke(selected ? Gallery.cobalt : Color.primary.opacity(palette.isLight ? 0.15 : 0), lineWidth: selected ? 2 : 1)
            if !selected || theme.id != "system" {
                Circle().fill(palette.accent.color).frame(width: 8, height: 8)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// A still drawing of the pill mid-recording, at its real size.
private struct PillSample: View {
    let theme: PillTheme

    var body: some View {
        let palette = theme.palette
        HStack(spacing: 10) {
            ZStack {
                Capsule().fill(palette.floor.color)
                Capsule().fill(LinearGradient(
                    colors: [palette.accent.alpha(0).color, palette.accent.alpha(0.5).color, palette.accent.alpha(0).color],
                    startPoint: .leading, endPoint: .trailing))
                HStack(spacing: 3) {
                    ForEach(Array([6.0, 12, 18, 10, 15, 8, 5].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(palette.foreground.color).frame(width: 2, height: height)
                    }
                }
            }
            .frame(height: 30)
            Text("0:07")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.foreground.color)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .frame(width: 220, height: 44)
        .background(Capsule().fill(palette.background.color))
        .shadow(color: .black.opacity(0.22), radius: 15, y: 10)
    }
}
