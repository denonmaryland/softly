import DictationCore
import Foundation
import whisper

/// Local Whisper transcription (whisper.cpp with Metal). The model stays
/// loaded so each dictation only pays for inference.
final class Transcriber: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case loading, ready, missingModel, failed
    }

    private let queue = DispatchQueue(label: "softly.whisper", qos: .userInitiated)
    private var context: OpaquePointer?

    deinit {
        if let context { whisper_free(context) }
    }

    func unload() {
        queue.async {
            if let context = self.context { whisper_free(context) }
            self.context = nil
        }
    }

    func load(from url: URL, completion: @escaping @Sendable (Status) -> Void) {
        queue.async {
            guard FileManager.default.fileExists(atPath: url.path) else {
                completion(.missingModel)
                return
            }
            if let old = self.context {
                whisper_free(old)
                self.context = nil
            }
            var params = whisper_context_default_params()
            params.use_gpu = true
            params.flash_attn = true
            self.context = whisper_init_from_file_with_params(url.path, params)
            completion(self.context == nil ? .failed : .ready)
        }
    }

    /// Calls back with cleaned text, or nil when nothing was said or decoding
    /// failed. `context` is the text just before this audio, when it is a
    /// later piece of a longer recording; it keeps spelling and casing in step.
    func transcribe(_ samples: [Float], context earlier: String = "", completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            guard let context = self.context else {
                completion(nil)
                return
            }
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.n_threads = Settings.threads
            params.translate = false
            params.no_context = true
            params.no_timestamps = true
            params.single_segment = false
            params.print_special = false
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.suppress_blank = true
            params.suppress_nst = true
            params.no_speech_thold = 0.6

            let audio = Transcript.padded(samples)
            let prompt = [Settings.initialPrompt, String(earlier.suffix(200))]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let result: Int32 = Settings.language.withCString { language in
                prompt.withCString { promptC in
                    params.language = language
                    params.initial_prompt = prompt.isEmpty ? nil : promptC
                    return audio.withUnsafeBufferPointer { buffer in
                        whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                    }
                }
            }
            guard result == 0 else {
                completion(nil)
                return
            }
            let count = whisper_full_n_segments(context)
            var segments: [String] = []
            for index in 0..<count {
                if let text = whisper_full_get_segment_text(context, index) {
                    segments.append(String(cString: text))
                }
            }
            completion(Transcript.clean(segments))
        }
    }
}
