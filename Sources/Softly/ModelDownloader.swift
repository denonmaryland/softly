import CryptoKit
import Foundation

/// Fetches a speech model into Application Support, with progress, and
/// verifies its SHA-256 before the engine loads it. Used on first run and
/// when a model that is not on disk yet is picked in Preferences.
@MainActor
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    enum State: Equatable {
        case idle, downloading(Double), verifying, failed(String)
    }

    private(set) var state: State = .idle { didSet { onChange() } }
    /// The model being fetched, while state is downloading or verifying.
    private(set) var model: SpeechModel?
    var onChange: () -> Void = {}
    /// The file is in place and verified; the engine should switch to it.
    var onComplete: (SpeechModel) -> Void = { _ in }

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    nonisolated(unsafe) private var lastStep = -1

    /// Downloads the given model, replacing a download of another one.
    func start(_ model: SpeechModel) {
        if self.model == model, state == .verifying { return }
        if self.model == model, case .downloading = state { return }
        task?.cancel()
        parakeetTask?.cancel()
        if model.engine == .parakeet {
            startParakeet(model)
            return
        }
        self.model = model
        lastStep = -1
        state = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        // The file for the current language; both names travel with the task.
        let task = session.downloadTask(with: model.file.url)
        task.taskDescription = model.id + "|" + model.file.name
        self.task = task
        task.resume()
    }

    private var parakeetTask: Task<Void, Never>?

    /// FluidAudio fetches and checks Parakeet's files into its own cache.
    private func startParakeet(_ model: SpeechModel) {
        self.model = model
        state = .downloading(0)
        parakeetTask = Task { [weak self] in
            do {
                try await ParakeetTranscriber.download { fraction in
                    Task { @MainActor in
                        guard let self, self.model == model, case .downloading = self.state else { return }
                        self.state = .downloading(min(fraction, 1))
                    }
                }
                guard let self, !Task.isCancelled, self.model == model else { return }
                self.model = nil
                self.state = .idle
                self.onComplete(model)
            } catch {
                guard let self, !Task.isCancelled, self.model == model else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        parakeetTask?.cancel()
        task?.cancel()
        task = nil
        model = nil
        state = .idle
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let step = Int(progress * 200)
        guard step != lastStep else { return }
        lastStep = step
        Task { @MainActor in
            if case .downloading = self.state { self.state = .downloading(progress) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns, so move it first.
        let fm = FileManager.default
        guard let parts = downloadTask.taskDescription?.split(separator: "|"), parts.count == 2,
              let file = SpeechModel.file(named: String(parts[1])) else { return }
        let model = SpeechModel.with(id: String(parts[0]))
        let staging = fm.temporaryDirectory.appendingPathComponent("softly-model-\(UUID().uuidString).bin")
        do {
            try fm.moveItem(at: location, to: staging)
        } catch {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
            return
        }
        Task { @MainActor in self.state = .verifying }
        guard Self.sha256Hex(of: staging) == file.sha256 else {
            try? fm.removeItem(at: staging)
            Task { @MainActor in self.state = .failed("The download did not verify. Try again.") }
            return
        }
        do {
            try fm.createDirectory(at: Settings.modelDirectory, withIntermediateDirectories: true)
            let destination = Settings.modelDirectory.appendingPathComponent(file.name)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: staging, to: destination)
            Task { @MainActor in
                self.model = nil
                self.state = .idle
                self.onComplete(model)
            }
        } catch {
            try? fm.removeItem(at: staging)
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
    }

    nonisolated private static func sha256Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
