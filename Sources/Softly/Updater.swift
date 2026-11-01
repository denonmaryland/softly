import AppKit
import Foundation

/// Checks GitHub Releases for a newer Softly and swaps it in. The release
/// asset is the zipped app bundle that CI builds for every tag.
@MainActor
final class Updater {
    struct Release: Sendable {
        let version: String
        let url: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(String), downloading, failed(String)
    }

    nonisolated static let repo = "denonmaryland/softly"
    nonisolated static let assetName = "Softly-mac.zip"
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private(set) var state: State = .idle { didSet { onChange() } }
    private(set) var release: Release?
    var onChange: () -> Void = {}
    private var periodic: Timer?

    init() {
        // A previous update leaves the old bundle beside the new one until the next launch.
        let previous = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Softly.previous.app")
        try? FileManager.default.removeItem(at: previous)
    }

    /// Quiet check shortly after launch and every six hours; only an
    /// available update changes anything visible.
    func startBackgroundChecks() {
        after(5) { [weak self] in self?.check(quiet: true) }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(quiet: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodic = timer
    }

    func check(quiet: Bool = false) {
        if state == .checking || state == .downloading { return }
        if case .available = state, quiet { return }
        state = .checking
        Task {
            do {
                let found = try await Self.fetchLatest()
                if Self.isNewer(found.version, than: Self.currentVersion) {
                    release = found
                    state = .available(found.version)
                } else {
                    state = quiet ? .idle : .upToDate
                }
            } catch {
                state = quiet ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Downloads the zip, unpacks it, swaps the bundle and relaunches.
    func install() {
        guard let release, state != .downloading else { return }
        state = .downloading
        Task {
            do {
                let (file, _) = try await URLSession.shared.download(from: release.url)
                let bundle = Bundle.main.bundleURL
                try await Task.detached { try Self.swap(zip: file, into: bundle) }.value
                NSApp.terminate(nil)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Softly/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.noRelease }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String) == assetName }),
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { throw UpdateError.noRelease }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url)
    }

    /// Numeric dotted comparison: 0.2.0 is newer than 0.1.10.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated private static func swap(zip: URL, into current: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("softly-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let fresh = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.badArchive }
        // CI builds are ad-hoc signed; without this Gatekeeper refuses the download.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])
        let previous = current.deletingLastPathComponent().appendingPathComponent("Softly.previous.app")
        try? fm.removeItem(at: previous)
        try fm.moveItem(at: current, to: previous)
        do {
            try fm.moveItem(at: fresh, to: current)
        } catch {
            try? fm.moveItem(at: previous, to: current)
            throw error
        }
        // Relaunch once this process has exited.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(current.path)\""]
        try relaunch.run()
    }

    nonisolated private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.commandFailed(path) }
    }
}

enum UpdateError: LocalizedError {
    case noRelease, badArchive, commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRelease: return "No release found"
        case .badArchive: return "The download was not an app"
        case .commandFailed(let c): return "\(c) failed"
        }
    }
}
