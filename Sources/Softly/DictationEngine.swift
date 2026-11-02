import AppKit
import DictationCore

/// Recording lifecycle, matching the Linux plugin:
/// tap/hold → record → transcribe → paste → ✓ → close.
/// Esc or clicking × cancels and discards at any point.
@MainActor
final class DictationEngine {
    let pill: PillModel
    private(set) var state: RecorderState = .idle
    private(set) var modelStatus: Transcriber.Status = .loading
    var onStatusChange: () -> Void = {}

    private var controller = GestureController()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private var capTimer: Timer?
    /// Bumped on every start/cancel so stale timers and results are ignored.
    private var session = 0

    init(pill: PillModel) {
        self.pill = pill
        pill.levelSource = { [recorder] in recorder.currentRMS }
        pill.onCancelClick = { [weak self] in self?.cancelNow() }
        // Input device changed mid-recording: keep what was captured and transcribe it.
        recorder.onInterrupted = { [weak self] in self?.handle(.stop) }
    }

    func loadModel() {
        modelStatus = .loading
        onStatusChange()
        transcriber.load(from: Settings.modelURL) { status in
            Task { @MainActor [weak self] in
                self?.modelStatus = status
                self?.onStatusChange()
            }
        }
    }

    // MARK: Inputs

    func press() { handle(.press) }
    func release() { handle(.release) }
    func toggle() { handle(.toggle) }

    /// Another key typed while Right Option is held: an Option shortcut, not dictation.
    func chord() {
        guard state == .recording, controller.held, !controller.locked else { return }
        handle(.cancel)
    }

    /// Esc: swallowed only while the pill is up.
    func escape() -> Bool {
        guard pill.showing else { return false }
        cancelNow()
        return true
    }

    func cancelNow() {
        if pill.previewing {
            session += 1
            hidePill(silent: true)
        } else if state == .idle {
            hidePill()
        } else {
            handle(.cancel)
        }
    }

    /// Silent simulated cycle: never opens the microphone or pastes.
    func preview() {
        guard state == .idle else { return }
        session += 1
        let token = session
        pill.beginSession(preview: true)
        after(3.2) { [weak self] in if self?.session == token { self?.pill.setDisplay(.transcribing) } }
        after(4.6) { [weak self] in if self?.session == token { self?.pill.setDisplay(.complete) } }
        after(5.2) { [weak self] in if self?.session == token { self?.hidePill(silent: true) } }
    }

    // MARK: Gesture actions

    private func handle(_ event: GestureEvent) {
        controller.tapToStart = Settings.tapToStart
        let actions = controller.send(event, now: PillModel.now, state: state)
        for action in actions {
            switch action {
            case .start:
                startRecording()
            case .stop:
                stopRecording()
            case .cancel:
                discard()
            }
        }
    }

    private func startRecording() {
        guard modelStatus == .ready, Permissions.microphoneGranted else {
            NSSound.beep()
            if !Permissions.microphoneGranted { Permissions.requestMicrophone() }
            _ = controller.send(.reset, now: PillModel.now, state: .idle)
            onStatusChange()
            return
        }
        do {
            try recorder.start()
        } catch {
            NSSound.beep()
            _ = controller.send(.reset, now: PillModel.now, state: .idle)
            return
        }
        session += 1
        state = .recording
        pill.beginSession()
        Sounds.playOpen()
        MediaPauser.shared.pause()
        capTimer = scheduled(Settings.maxDuration) { [weak self] in self?.handle(.stop) }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        capTimer?.invalidate()
        let (samples, peak) = recorder.stop()
        MediaPauser.shared.resume()
        state = .transcribing
        _ = controller.send(.reset, now: PillModel.now, state: state)
        pill.setDisplay(.transcribing)

        // Too short, or silent: Whisper tends to invent text for silence.
        guard Double(samples.count) / 16_000 >= Settings.minimumSpeech, peak >= Settings.silenceRMS else {
            finish(nil)
            return
        }
        let token = session
        transcriber.transcribe(samples) { text in
            Task { @MainActor [weak self] in
                guard let self, self.session == token, self.state == .transcribing else { return }
                self.finish(text)
            }
        }
    }

    private func finish(_ text: String?) {
        state = .idle
        _ = controller.send(.reset, now: PillModel.now, state: state)
        guard let text else {
            hidePill()
            return
        }
        Paster.paste(text)
        // Let the paste land, confirm with ✓, then close.
        let token = session
        after(0.075) { [weak self] in
            guard let self, self.session == token else { return }
            self.pill.setDisplay(.complete)
            after(0.45) { [weak self] in
                guard let self, self.session == token else { return }
                self.hidePill()
            }
        }
    }

    private func discard() {
        session += 1
        capTimer?.invalidate()
        if state == .recording {
            recorder.stop()
            MediaPauser.shared.resume()
        }
        state = .idle
        hidePill()
    }

    private func hidePill(silent: Bool = false) {
        guard pill.showing else { return }
        let wasPreview = pill.previewing
        pill.hide()
        if !silent && !wasPreview { Sounds.playClose() }
    }

    private func scheduled(_ seconds: Double, _ body: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
