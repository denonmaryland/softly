import Foundation

/// The speech models Softly offers. All three are whisper.cpp files from the
/// same Hugging Face repo, so the engine and the download path are shared;
/// they trade size and speed for accuracy. Same list, ids and checksums as
/// Windows/Softly/SpeechModel.cs.
struct SpeechModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let fileName: String
    let sha256: String
    let sizeMB: Int

    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    static let fast = SpeechModel(
        id: "fast", name: "Fast", detail: "Smallest and quickest. Fine for short, plain sentences.",
        fileName: "ggml-base.en-q5_1.bin",
        sha256: "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", sizeMB: 60)
    static let balanced = SpeechModel(
        id: "balanced", name: "Balanced", detail: "The default. Quick, and good with everyday speech.",
        fileName: "ggml-small.en-q5_1.bin",
        sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30", sizeMB: 190)
    static let accurate = SpeechModel(
        id: "accurate", name: "Accurate", detail: "Best with names, code and technical words. A little slower.",
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", sizeMB: 574)

    static let all = [fast, balanced, accurate]

    static func with(id: String) -> SpeechModel {
        all.first { $0.id == id } ?? balanced
    }

    static var current: SpeechModel { with(id: Settings.speechModel) }

    /// Where this model lives, or would live once downloaded. A copy bundled
    /// in the app wins; the balanced model also looks in the folder used
    /// before the app was renamed from Quiet Dictation.
    var fileURL: URL {
        if let bundled = Bundle.main.url(forResource: fileName, withExtension: nil) { return bundled }
        let current = Settings.modelDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuietDictation/Models/\(fileName)")
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return current
    }

    var isDownloaded: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}
