import AppKit
import SwiftUI

/// `Softly --snapshot <folder>` draws every window screen to a PNG and quits,
/// so the layout can be checked without a screen (over SSH, in CI). Live
/// AppKit controls such as menus and text editors may draw empty here.
@MainActor
enum Snapshots {
    static func runIfAsked(state: AppState) -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for appearance in ["light", "dark"] {
            for section in WindowSection.allCases {
                state.section = section
                let view = MainView(state: state, scrolls: false)
                    .frame(width: 1040, height: 720)
                    .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: folder.appendingPathComponent("\(appearance)-\(section.rawValue.lowercased()).png"))
            }
        }
        return true
    }
}
