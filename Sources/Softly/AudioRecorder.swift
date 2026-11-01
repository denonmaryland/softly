import AVFoundation
import DictationCore

enum RecorderError: Error {
    case noInputDevice
    case converterUnavailable
}

/// Captures the default input, converts to 16 kHz mono Float32 for Whisper,
/// and publishes a live RMS level for the waveform. Audio stays in memory only.
final class AudioRecorder: @unchecked Sendable {
    /// Called on the main queue when the input device changes mid-recording
    /// (for example AirPods connecting). Capture has already stopped.
    var onInterrupted: () -> Void = {}

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Double = 0
    private var peak: Double = 0
    private var converter: AVAudioConverter?
    private var running = false
    private var configObserver: NSObjectProtocol?
    private let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    var currentRMS: Double { lock.withLock { level } }

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: format, to: whisperFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(16_000 * 60)
            level = 0
            peak = 0
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.onInterrupted()
        }
    }

    /// Stops capture and returns the 16 kHz samples plus the loudest RMS seen.
    @discardableResult
    func stop() -> (samples: [Float], peak: Double) {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
            configObserver = nil
            // A fresh engine picks up the current default device and format next time.
            engine = AVAudioEngine()
        }
        converter = nil
        return lock.withLock {
            let result = (samples, peak)
            samples = []
            level = 0
            peak = 0
            return result
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        if let channels = buffer.floatChannelData {
            let rms = rootMeanSquare(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            lock.withLock {
                level = rms
                peak = max(peak, rms)
            }
        }
        guard let converter else { return }
        let ratio = whisperFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return }
        let feed = OneShotInput(buffer)
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in feed.next(status) }
        guard error == nil, let data = out.floatChannelData else { return }
        let chunk = UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}

/// Supplies one buffer to AVAudioConverter, then reports "no data for now"
/// so the converter keeps its resampler state for the next buffer.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
