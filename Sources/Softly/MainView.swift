import AppKit
import SwiftUI

enum WindowSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case vocabulary = "Vocabulary"
    case preferences = "Preferences"

    var id: String { rawValue }
}

/// Sidebar on the left, a 66 pt header and the selected view on the right.
/// Sizes and spacing follow docs/ui-spec.md; colours are the system's
/// semantic ones so dark mode comes for free.
struct MainView: View {
    @ObservedObject var state: AppState
    @State private var section: WindowSection = .home

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                header
                ScrollView {
                    content
                        .frame(maxWidth: 724, alignment: .leading)
                        .padding(.leading, 48)
                        .padding(.trailing, 48)
                        .padding(.top, 40)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(section.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 34)
            .frame(height: 66)
            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home: HomeView(state: state)
        case .vocabulary: VocabularyView(state: state)
        case .preferences: PreferencesView(state: state)
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @Binding var section: WindowSection

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarMaterial()
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    Text("Softly")
                        .font(.system(size: 16, weight: .bold))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)

                VStack(spacing: 7) {
                    ForEach(WindowSection.allCases) { item in
                        SidebarItem(title: item.rawValue, selected: item == section) {
                            section = item
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 7) {
                    Text("ON THIS MAC")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Whisper · English")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.8))
                    Text("Audio held in memory only")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 10)
                .padding(.bottom, 2)
            }
            // Top padding clears the traffic lights, which sit over the sidebar.
            .padding(.top, 52)
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Standard sidebar material, so the window looks like every other Mac app.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
