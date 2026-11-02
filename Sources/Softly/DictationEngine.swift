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
    /// The last few dictations, newest first. Held in memory only, like the
    /// Linux popover's list, so nothing said is ever written to disk.
    private(set) var recent: [String] = []

    private var controller = GestureController()
    private let recorder = AudioRecorder()
    private let whisper = Transcriber()
    private let parakeet = ParakeetTranscriber()
    /// The engine the current speech model uses; set by loadModel.
    private var transcriber: SpeechBackend
    private var capTimer: Timer?
    /// Transcribing while you talk: pieces of a long recording, in order,
    /// filled in as they finish; `committed` samples have been handed out.
    private var pieces: [String?] = []
    private var piecesDone = 0
    private var committed = 0
    private var chunkTimer: Timer?
    private var chunkInFlight = false
    /// Bumped on every start/cancel so stale timers and results are ignored.
    private var session = 0

    init(pill: PillModel) {
        self.pill = pill
        transcriber = SpeechModel.current.engine == .parakeet ? parakeet : whisper
        pill.levelSource = { [recorder] in recorder.currentRMS }
        pill.onCancelClick = { [weak self] in self?.cancelNow() }
        // Input device changed mid-recording: keep what was captured and transcribe it.
        recorder.onInterrupted = { [weak self] in self?.handle(.stop) }
    }

    func loadModel() {
        modelStatus = .loading
        onStatusChange()
        let next: SpeechBackend = SpeechModel.current.engine == .parakeet ? parakeet : whisper
        if next !== transcriber { transcriber.unload() }
        transcriber = next
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
        pieces = []
        piecesDone = 0
        committed = 0
        chunkInFlight = false
        chunkTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.transcribeAhead() }
        }
        RunLoop.main.add(timer, forMode: .common)
        chunkTimer = timer
    }

    /// Once a second while recording: when enough audio has piled up and
    /// there is a pause to cut at, transcribe up to it in the background.
    private func transcribeAhead() {
        guard state == .recording, !chunkInFlight else { return }
        let pending = recorder.pending(from: committed)
        guard let cut = Chunking.cut(pending) else { return }
        let audio = Array(pending[..<cut])
        committed += cut
        chunkInFlight = true
        let index = pieces.count
        pieces.append(nil)
        let token = session
        transcriber.transcribe(audio, context: Chunking.join(pieces) ?? "") { text in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.chunkInFlight = false
                self.pieceFinished(index, text)
            }
        }
    }

    private func pieceFinished(_ index: Int, _ text: String?) {
        pieces[index] = text
        piecesDone += 1
        // All pieces in, including the last one queued at stop: finish.
        if state == .transcribing, piecesDone == pieces.count {
            finish(Chunking.join(pieces))
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        capTimer?.invalidate()
        chunkTimer?.invalidate()
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
        guard committed > 0 else {
            transcriber.transcribe(samples, context: "") { text in
                Task { @MainActor [weak self] in
                    guard let self, self.session == token, self.state == .transcribing else { return }
                    self.finish(text)
                }
            }
            return
        }
        // Earlier pieces were transcribed while recording; only the rest is left.
        let tail = committed < samples.count ? Array(samples[committed...]) : []
        guard Double(tail.count) / 16_000 >= Settings.minimumSpeech,
              Double(Chunking.loudest(tail)) >= Settings.silenceRMS else {
            if piecesDone == pieces.count { finish(Chunking.join(pieces)) }
            return
        }
        let index = pieces.count
        pieces.append(nil)
        transcriber.transcribe(tail, context: Chunking.join(pieces) ?? "") { text in
            Task { @MainActor [weak self] in
                guard let self, self.session == token, self.state == .transcribing else { return }
                self.pieceFinished(index, text)
            }
        }
    }

    private func finish(_ transcript: String?) {
        state = .idle
        _ = controller.send(.reset, now: PillModel.now, state: state)
        // "Heard this, type that" fixes, then a final spoken "submit".
        var text = transcript.map { Replacements.apply($0, Settings.replacements) }
        var submit = false
        if Settings.submitWord, let fixed = text {
            let parts = SubmitWord.split(fixed)
            text = parts.text
            submit = parts.submit
        }
        // A transcript that was all filler is dropped, unless it said "submit".
        guard let text, !text.isEmpty || submit else {
            hidePill()
            return
        }
        if !text.isEmpty {
            recent = [text] + recent.filter { $0 != text }.prefix(4)
        }
        Paster.paste(text, submit: submit)
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
        chunkTimer?.invalidate()
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
