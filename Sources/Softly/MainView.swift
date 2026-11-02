import AppKit
import SwiftUI

enum WindowSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case speech = "Speech"
    case words = "Words"
    case shortcut = "Shortcut"
    case look = "Look"
    case about = "About"

    var id: String { rawValue }
}

/// Sidebar on the left, the selected screen on the right (Paper
/// "A · Gallery", page 0.3 · Redesign).
struct MainView: View {
    @ObservedObject var state: AppState
    /// Off for --snapshot: ImageRenderer cannot draw an AppKit scroll view.
    var scrolls = true

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state)
                .frame(width: 220)
            Rectangle().fill(Gallery.hairline).frame(width: 1)
            Group {
                if scrolls {
                    ScrollView { page }
                } else {
                    page.frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Gallery.page)
        .frame(minWidth: 860, minHeight: 600)
    }

    private var page: some View {
        content
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 56)
            .padding(.top, 44)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch state.section {
        case .home: HomeView(state: state)
        case .speech: SpeechView(state: state)
        case .words: WordsView(state: state)
        case .shortcut: ShortcutView(state: state)
        case .look: LookView(state: state)
        case .about: AboutView(state: state)
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            HStack(spacing: 10) {
                Circle().fill(Gallery.cobalt).frame(width: 22, height: 22)
                Text("Softly")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.4)
            }
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(WindowSection.allCases) { item in
                    SidebarItem(title: item.rawValue, selected: item == state.section) {
                        state.section = item
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.ready ? Gallery.ready : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(state.ready ? "Ready" : "Needs attention")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(state.ready ? "Tap \(state.hotkey.label) to dictate" : state.statusLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 14)
        }
        // Top padding clears the traffic lights, which sit over the sidebar.
        .padding(.top, 52)
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .padding(.bottom, 28)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A fixed 14 pt slot holds the cobalt dot, so every title shares one edge.
private struct SidebarItem: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    if selected {
                        Circle().fill(Gallery.cobalt).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 14, alignment: .leading)
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
