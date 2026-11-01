import Foundation

/// Runs `body` on the main actor after `seconds`.
func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        body()
    }
}
