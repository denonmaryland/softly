import AppKit
import SwiftUI

/// The window's visual language ("A · Gallery" in Paper, page 0.3 · Redesign):
/// Swiss editorial type, one cobalt accent, hairline rules, and settings that
/// sit straight on the page in two columns: a label on the left, controls on
/// the right. Text and rules use semantic colours so dark mode still works.
enum Gallery {
    /// #1F4FFF, lifted to #6A8BFF in dark mode so links stay readable.
    static let cobalt = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x6A / 255, green: 0x8B / 255, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0x1F / 255, green: 0x4F / 255, blue: 1, alpha: 1)
    })
    static let ready = Color(red: 0x1F / 255, green: 0x9D / 255, blue: 0x55 / 255)
    static var hairline: Color { Color(nsColor: .separatorColor) }
    static var page: Color { Color(nsColor: .textBackgroundColor) }
    static var well: Color { Color.primary.opacity(0.045) }
    /// Width of the label column in every section.
    static let labelWidth: CGFloat = 170
}

/// Large title and a one-line explanation at the top of each screen.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.5)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 36)
    }
}

/// One section: a rule across the top, the label column, then the controls.
/// The first section on a page gets the strong rule.
struct GallerySection<Content: View>: View {
    let title: String
    var detail: String? = nil
    var first = false
    /// Extra content under the label, such as a keycap.
    var aside: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(first ? Color.primary.opacity(0.85) : Gallery.hairline)
                .frame(height: 1)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let aside {
                        aside.padding(.top, 6)
                    }
                }
                .frame(width: Gallery.labelWidth, alignment: .leading)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }
}

/// A title, a muted line under it and a control on the right; rows inside a
/// section are separated by hairlines.
struct GalleryRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var divider = true
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.vertical, 14)
            if divider {
                Rectangle().fill(Gallery.hairline).frame(height: 1)
            }
        }
    }
}

/// The cobalt switch used everywhere.
struct GallerySwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Gallery.cobalt)
    }
}

/// A rounded pill: filled ink when selected, outlined otherwise.
struct ChoicePill<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color(nsColor: .textBackgroundColor) : Color.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? Color.primary : Color.clear))
                .overlay(Capsule().stroke(selected ? Color.clear : Gallery.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A text button in cobalt, the window's "link" style.
struct CobaltLink: View {
    let title: String
    var weight: Font.Weight = .medium
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(Gallery.cobalt)
    }
}

/// "Right ⌥" drawn as a physical key: hairline border and a thicker lip.
struct Keycap: View {
    let label: String
    var large = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 17 : 13, weight: .semibold))
            .padding(.vertical, large ? 10 : 6)
            .padding(.horizontal, large ? 16 : 10)
            .background(
                RoundedRectangle(cornerRadius: large ? 8 : 6, style: .continuous)
                    .fill(Gallery.page)
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? 8 : 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.primary.opacity(0.18), radius: 0, x: 0, y: 2)
    }
}

/// Lays children out left to right and wraps, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
