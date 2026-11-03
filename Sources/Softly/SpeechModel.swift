import DictationCore
import Foundation

/// The speech models Softly offers. All are whisper.cpp files from the same
/// Hugging Face repo, so the engine and the download path are shared; they
/// trade size and speed for accuracy. Fast and Balanced come as an
/// English-only file and a multilingual one, picked by the language setting.
/// Same list, ids and checksums as Windows/Softly/SpeechModel.cs.
struct SpeechModel: Identifiable, Equatable, Sendable {
    struct File: Equatable, Sendable {
        let name: String
        let sha256: String
        let sizeMB: Int

        var url: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)")!
        }
    }

    enum Engine: Sendable { case whisper, parakeet }

    let id: String
    let name: String
    let detail: String
    let english: File
    let multilingual: File
    var engine: Engine = .whisper

    static let fast = SpeechModel(
        id: "fast", name: "Fast", detail: "Smallest and quickest. Fine for short, plain sentences.",
        english: File(name: "ggml-base.en-q5_1.bin", sha256: "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", sizeMB: 60),
        multilingual: File(name: "ggml-base-q5_1.bin", sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898", sizeMB: 60))
    static let balanced = SpeechModel(
        id: "balanced", name: "Balanced", detail: "The default. Quick, and good with everyday speech.",
        english: File(name: "ggml-small.en-q5_1.bin", sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30", sizeMB: 190),
        multilingual: File(name: "ggml-small-q5_1.bin", sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", sizeMB: 190))
    static let accurate: SpeechModel = {
        let turbo = File(name: "ggml-large-v3-turbo-q5_0.bin", sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", sizeMB: 574)
        return SpeechModel(id: "accurate", name: "Accurate", detail: "Best with names, code and technical words. A little slower.",
                           english: turbo, multilingual: turbo)
    }()

    /// NVIDIA Parakeet TDT v3 on the Neural Engine through FluidAudio, which
    /// downloads and keeps its own files. It detects 25 European languages by
    /// itself; vocabulary goes through FluidAudio's keyword spotter instead of a prompt.
    static let parakeet: SpeechModel = {
        let files = File(name: "parakeet-tdt-0.6b-v3-coreml", sha256: "", sizeMB: 480)
        return SpeechModel(id: "parakeet", name: "Parakeet", detail: "Very fast on the Neural Engine. 25 languages.",
                           english: files, multilingual: files, engine: .parakeet)
    }()

    static let all = [fast, balanced, accurate, parakeet]

    static func with(id: String) -> SpeechModel {
        all.first { $0.id == id } ?? balanced
    }

    static var current: SpeechModel { with(id: Settings.speechModel) }

    /// Any model file by name, for a download that finishes later.
    static func file(named name: String) -> File? {
        all.filter { $0.engine == .whisper }.flatMap { [$0.english, $0.multilingual] }.first { $0.name == name }
    }

    /// The file this model needs for the language setting.
    var file: File { Languages.needsMultilingual(Settings.language) ? multilingual : english }

    var sizeMB: Int { file.sizeMB }

    /// Where the file lives, or would live once downloaded. A copy bundled
    /// in the app wins; the old Quiet Dictation folder is also checked.
    static func url(of file: File) -> URL {
        if let bundled = Bundle.main.url(forResource: file.name, withExtension: nil) { return bundled }
        let current = Settings.modelDirectory.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuietDictation/Models/\(file.name)")
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return current
    }

    var fileURL: URL { Self.url(of: file) }

    var isDownloaded: Bool {
        engine == .parakeet ? ParakeetTranscriber.modelsReady : FileManager.default.fileExists(atPath: fileURL.path)
    }
}
