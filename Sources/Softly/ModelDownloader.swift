import CryptoKit
import Foundation

/// Fetches the speech model into Application Support on first run, with
/// progress, and verifies it before the engine loads it. The same file the
/// Linux and Windows builds use.
@MainActor
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    enum State: Equatable {
        case idle, downloading(Double), verifying, failed(String)
    }

    nonisolated static let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!
    nonisolated static let sha1 = "20f54878d608f94e4a8ee3ae56016571d47cba34"
    nonisolated static let sizeMB = 181

    private(set) var state: State = .idle { didSet { onChange() } }
    var onChange: () -> Void = {}
    /// The file is in place and verified; the engine should load it.
    var onComplete: () -> Void = {}

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    nonisolated(unsafe) private var lastStep = -1

    func start() {
        if case .downloading = state { return }
        if state == .verifying { return }
        lastStep = -1
        state = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: Self.url)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
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
        let staging = fm.temporaryDirectory.appendingPathComponent("softly-model-\(UUID().uuidString).bin")
        do {
            try fm.moveItem(at: location, to: staging)
        } catch {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
            return
        }
        Task { @MainActor in self.state = .verifying }
        guard Self.sha1Hex(of: staging) == Self.sha1 else {
            try? fm.removeItem(at: staging)
            Task { @MainActor in self.state = .failed("The download did not verify. Try again.") }
            return
        }
        do {
            try fm.createDirectory(at: Settings.modelDirectory, withIntermediateDirectories: true)
            let destination = Settings.modelDirectory.appendingPathComponent(Settings.modelFileName)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: staging, to: destination)
            Task { @MainActor in
                self.state = .idle
                self.onComplete()
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

    nonisolated private static func sha1Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
