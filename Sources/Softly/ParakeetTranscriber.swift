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
///
/// Parakeet takes no prompt, so the vocabulary works differently from
/// Whisper: FluidAudio's CTC keyword spotter (a small second model, fetched
/// once in the background) listens for the words and corrects the
/// transcript. Fix rules that type a vocabulary word are passed along as
/// its known mishearings.
final class ParakeetTranscriber: SpeechBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var manager: AsrManager?
    private var boost: VocabularyBoostingSession?
    /// The vocabulary the current (or pending) boost session was built for.
    private var boostKey = ""

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
                self.prepareVocabulary()
            } catch {
                completion(.failed)
            }
        }
    }

    /// Parakeet takes no prompt, so `context` is unused; pieces are joined as they are.
    func transcribe(_ samples: [Float], context: String, completion: @escaping @Sendable (String?) -> Void) {
        let (manager, boost) = lock.withLock { (self.manager, self.boost) }
        prepareVocabulary()
        Task {
            guard let manager else {
                completion(nil)
                return
            }
            do {
                let audio = Transcript.padded(samples)
                var state = TdtDecoderState.make()
                let result = try await manager.transcribe(audio, decoderState: &state)
                var text = result.text
                if let boost, let timings = result.tokenTimings, !timings.isEmpty {
                    text = await Self.boosted(text, timings: timings, audio: audio, session: boost)
                }
                completion(Transcript.clean([text]))
            } catch {
                completion(nil)
            }
        }
    }

    func unload() {
        lock.withLock {
            manager = nil
            boost = nil
            boostKey = ""
        }
    }

    /// Test hook for `Softly --transcribe`: waits for the boost session, then
    /// returns the transcript before and after vocabulary boosting. Written
    /// like transcribe(_:) on purpose: Swift 6.1.2 crashed compiling a
    /// variant with `try?` and lock closures here.
    func compare(_ samples: [Float]) async -> (raw: String, boosted: String?)? {
        prepareVocabulary()
        for _ in 0..<600 {
            lock.lock()
            let waiting = boost == nil && !boostKey.isEmpty
            lock.unlock()
            if !waiting { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        lock.lock()
        let manager = self.manager
        let boost = self.boost
        lock.unlock()
        guard let manager else { return nil }
        let audio = Transcript.padded(samples)
        do {
            var state = TdtDecoderState.make()
            let result = try await manager.transcribe(audio, decoderState: &state)
            var boosted: String?
            if let boost, let timings = result.tokenTimings {
                boosted = await Self.boosted(result.text, timings: timings, audio: audio, session: boost)
            }
            return (result.text, boosted)
        } catch {
            return nil
        }
    }

    /// Only the word swaps the spotter is sure of, applied to Parakeet's own
    /// text with the fix-rule matcher. FluidAudio's rebuilt sentence drops
    /// commas and small words, so it is not used as-is.
    private static func boosted(_ text: String, timings: [TokenTiming], audio: [Float],
                                session: VocabularyBoostingSession) async -> String {
        guard let output = await session.rescore(text: text, tokenTimings: timings, audioSamples: audio) else { return text }
        let punctuation = CharacterSet.punctuationCharacters.union(.whitespaces)
        let swaps = output.replacements.compactMap { swap -> Replacement? in
            guard swap.shouldReplace, let to = swap.replacementWord else { return nil }
            // The spotter sometimes takes a small neighbouring word along
            // ("and Terra1" → "Terra One"); keep those words out of the swap.
            let keep = Set(to.lowercased().split(separator: " ").map(String.init))
            var words = swap.originalWord.trimmingCharacters(in: punctuation)
                .split(separator: " ").map { $0.trimmingCharacters(in: punctuation) }
            while let first = words.first, words.count > 1, smallWords.contains(first.lowercased()), !keep.contains(first.lowercased()) {
                words.removeFirst()
            }
            while let last = words.last, words.count > 1, smallWords.contains(last.lowercased()), !keep.contains(last.lowercased()) {
                words.removeLast()
            }
            let from = words.joined(separator: " ")
            guard !from.isEmpty, words.count <= 2, from != to else { return nil }
            // Sounding alike is not enough ("terrace" is not "Terra One"):
            // the heard word must also be spelled close to the term itself, or
            // match a mishearing already known from the fix rules.
            let aliases = session.vocabulary.terms.first { $0.text == to }?.aliases ?? []
            guard similarity(from, to) >= 0.8 || aliases.contains(where: { similarity(from, $0) >= 0.95 }) else { return nil }
            return Replacement(from: from, to: to)
        }
        return swaps.isEmpty ? text : Replacements.apply(text, swaps)
    }

    /// Builds the boost session for the current vocabulary when it changed,
    /// off the dictation path; the previous session keeps working meanwhile.
    /// The first time, this downloads the keyword model (about 100 MB).
    private func prepareVocabulary() {
        let words = Settings.vocabulary.filter { $0.count >= 3 }
        let fixes = Settings.replacements
        // Mishearings already known from the fix rules, per vocabulary word.
        let terms = words.map { word -> CustomVocabularyTerm in
            let heard = fixes.filter { $0.to.caseInsensitiveCompare(word) == .orderedSame }.map(\.from)
            return CustomVocabularyTerm(text: word, aliases: heard.isEmpty ? nil : heard)
        }
        let key = terms.map { $0.text + ":" + ($0.aliases ?? []).joined(separator: ",") }.joined(separator: "|")
        let changed: Bool = lock.withLock {
            guard key != boostKey else { return false }
            boostKey = key
            if words.isEmpty { boost = nil }
            return !words.isEmpty
        }
        guard changed else { return }
        Task.detached(priority: .utility) { [weak self] in
            do {
                let models = try await CtcModels.downloadAndLoad()
                // The acoustic "rescue" pass rewrites ordinary words around a
                // name; with it off, the names are still found and the rest
                // of the sentence is left alone (tested on three voices).
                let session = try await VocabularyBoostingSession(
                    vocabulary: CustomVocabularyContext(terms: terms), ctcModels: models,
                    config: VocabularyRescorer.Config(spotterRescueEnabled: false))
                guard let self else { return }
                self.lock.withLock { if self.boostKey == key { self.boost = session } }
            } catch {
                // No boost this time; the next dictation tries again.
                guard let self else { return }
                self.lock.withLock { if self.boostKey == key { self.boostKey = "" } }
            }
        }
    }
}
