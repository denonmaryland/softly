import AppKit
import AVFoundation
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

/// `Softly --transcribe <file>` runs an audio file through Parakeet and
/// prints the transcript before and after vocabulary boosting, then quits.
@MainActor
enum TranscribeCheck {
    static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--transcribe"), flag + 1 < args.count else { return false }
        let url = URL(fileURLWithPath: args[flag + 1])
        Task {
            let parakeet = ParakeetTranscriber()
            let status = await withCheckedContinuation { done in
                parakeet.load(from: url) { done.resume(returning: $0) }
            }
            guard status == .ready, let samples = readAudio(url) else {
                print("not ready: \(status)")
                exit(1)
            }
            if let result = await parakeet.compare(samples) {
                print("RAW:     \(result.raw)")
                print("BOOSTED: \(result.boosted ?? "(no vocabulary)")")
            }
            exit(0)
        }
        return true
    }

    private static func readAudio(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        converter.convert(to: output, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard let data = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
