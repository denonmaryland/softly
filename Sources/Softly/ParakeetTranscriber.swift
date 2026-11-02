import DictationCore
import FluidAudio
import Foundation

/// The two engines behind one interface: whisper.cpp (Transcriber) and
/// Parakeet (ParakeetTranscriber). DictationEngine talks to whichever the
/// current speech model uses.
protocol SpeechBackend: AnyObject, Sendable {
    func load(from url: URL, completion: @escaping @Sendable (Transcriber.Status) -> Void)
    func transcribe(_ samples: [Float], context: String, completion: @escaping @Sendable (String?) -> Void)
    /// Frees the model's memory when the other engine takes over.
    func unload()
}

extension Transcriber: SpeechBackend {}

/// NVIDIA Parakeet TDT v3 through FluidAudio, on the Neural Engine. The model
/// files live in FluidAudio's cache; ModelDownloader fetches them.
final class ParakeetTranscriber: SpeechBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var manager: AsrManager?

    static var cacheDirectory: URL { AsrModels.defaultCacheDirectory(for: .v3) }

    static var modelsReady: Bool { AsrModels.modelsExist(at: cacheDirectory, version: .v3) }

    /// Downloads the model files, reporting progress from 0 to 1.
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await AsrModels.download(version: .v3) { update in progress(update.fractionCompleted) }
    }

    func load(from url: URL, completion: @escaping @Sendable (Transcriber.Status) -> Void) {
        Task {
            guard Self.modelsReady else {
                completion(.missingModel)
                return
            }
            do {
                let models = try await AsrModels.load(from: Self.cacheDirectory, version: .v3)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                lock.withLock { self.manager = manager }
                completion(.ready)
            } catch {
                completion(.failed)
            }
        }
    }

    /// Parakeet takes no prompt, so `context` is unused; pieces are joined as they are.
    func transcribe(_ samples: [Float], context: String, completion: @escaping @Sendable (String?) -> Void) {
        let manager = lock.withLock { self.manager }
        Task {
            guard let manager else {
                completion(nil)
                return
            }
            do {
                var state = TdtDecoderState.make()
                let result = try await manager.transcribe(Transcript.padded(samples), decoderState: &state)
                completion(Transcript.clean([result.text]))
            } catch {
                completion(nil)
            }
        }
    }

    func unload() {
        lock.withLock { manager = nil }
    }
}
