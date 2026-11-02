import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let pill = PillModel()
    private let downloader = ModelDownloader()
    private let state = AppState()
    private lazy var engine = DictationEngine(pill: pill)
    private lazy var panel = PillPanel.make(model: pill)
    private lazy var mainWindow = MainWindow(state: state)
    private let hotkeys = HotkeyMonitor()
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var permissionRetry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        pill.onScreenChange = { [weak self] visible in
            guard let self else { return }
            if visible { self.panel.present() } else { self.panel.orderOut(nil) }
        }
        _ = panel // create now so pointer tracking is wired before first use

        hotkeys.onPress = { [weak self] in self?.engine.press() }
        hotkeys.onRelease = { [weak self] in self?.engine.release() }
        hotkeys.onChord = { [weak self] in self?.engine.chord() }
        hotkeys.onEscape = { [weak self] in self?.engine.escape() ?? false }
        hotkeys.hotkey = state.hotkey
        state.applyHotkey = { [weak self] key in self?.hotkeys.hotkey = key }
        state.captureHotkey = { [weak self] in self?.captureHotkey() }
        state.cancelCapture = { [weak self] in
            self?.hotkeys.onCapture = nil
            self?.state.capturingHotkey = false
        }

        engine.onStatusChange = { [weak self] in self?.refresh() }
        engine.onDictated = { [weak self] text in self?.state.addRecent(text) }
        state.poll = { [weak self] in self?.refresh() }
        state.showModelFolder = { [weak self] in self?.showModelFolder() }
        state.reloadModel = { [weak self] in self?.engine.loadModel() }
        state.downloadModel = { [weak self] in self?.downloader.start(SpeechModel.current) }
        state.cancelDownload = { [weak self] in self?.downloader.cancel() }
        state.chooseModel = { [weak self] id in self?.chooseModel(id) }
        state.chooseLanguage = { [weak self] code in self?.chooseLanguage(code) }
        downloader.onChange = { [weak self] in
            guard let self else { return }
            self.state.modelDownload = self.downloader.state
            self.state.downloadingModel = self.downloader.model?.id
        }
        // A model picked in Preferences takes over once it is on disk.
        downloader.onComplete = { [weak self] model in self?.useModel(model.id) }
        state.previewPill = { [weak self] in self?.engine.preview() }
        state.checkForUpdates = { [weak self] in self?.updater.check() }
        state.installUpdate = { [weak self] in self?.updater.install() }
        updater.onChange = { [weak self] in
            guard let self else { return }
            self.state.update = self.updater.state
        }
        updater.startBackgroundChecks()

        if Snapshots.runIfAsked(state: state) {
            NSApp.terminate(nil)
            return
        }

        setUpMainMenu()
        setUpStatusItem()

        Permissions.requestMicrophone()
        startHotkeys()
        engine.loadModel()
        refresh()

        // Something still needs the user: open the window so the permissions
        // list and model status are in front of them.
        let modelPresent = FileManager.default.fileExists(atPath: Settings.modelURL.path)
        if !hotkeys.isRunning || !Permissions.microphoneGranted || !modelPresent {
            mainWindow.show()
        }
    }

    /// A downloaded model is switched to at once; otherwise it is fetched
    /// first and the current one keeps working meanwhile.
    private func chooseModel(_ id: String) {
        let model = SpeechModel.with(id: id)
        if model.isDownloaded {
            if downloader.model != nil { downloader.cancel() }
            useModel(id)
        } else {
            downloader.start(model)
        }
    }

    /// English uses the smaller English-only files; other languages need the
    /// multilingual one, fetched first if it is not on disk yet.
    private func chooseLanguage(_ code: String) {
        state.language = code
        let model = SpeechModel.current
        if model.isDownloaded {
            engine.loadModel()
        } else {
            downloader.start(model)
        }
    }

    private func useModel(_ id: String) {
        state.speechModel = id
        engine.loadModel()
    }

    /// Launching the app again (Finder, Launchpad, `open`) brings the window up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return false
    }

    // MARK: Hotkey permissions

    /// The next key pressed anywhere becomes the dictation key, if it can be one.
    private func captureHotkey() {
        guard hotkeys.isRunning else {
            state.hotkeyNote = "Grant Input Monitoring first, then pick a key."
            return
        }
        state.hotkeyNote = nil
        state.capturingHotkey = true
        hotkeys.onCapture = { [weak self] result in
            guard let self else { return }
            self.state.capturingHotkey = false
            switch result {
            case .key(let key): self.state.hotkey = key
            case .unsupported: self.state.hotkeyNote = "That key can't be used. Try \(Hotkey.choices)."
            case .cancelled: break
            }
            self.refresh()
        }
    }

    private func startHotkeys() {
        if hotkeys.start() { return }
        Permissions.requestKeyboard()
        // Keep trying quietly until Input Monitoring and Accessibility are granted.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if self.hotkeys.start() {
                    timer.invalidate()
                    self.permissionRetry = nil
                    self.refresh()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionRetry = timer
    }

    // MARK: State

    /// Pushes engine and hotkey state to the window and the menu-bar icon.
    private func refresh() {
        state.refresh(modelStatus: engine.modelStatus, hotkeysRunning: hotkeys.isRunning)
        let ready = engine.modelStatus == .ready && hotkeys.isRunning
        let symbol = ready ? "waveform" : "waveform.badge.exclamationmark"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Softly")
    }

    // MARK: Main menu

    /// The app has no Dock icon, but its window still needs ⌘-shortcuts:
    /// Edit for the practice box (the paste itself arrives as ⌘V), Window
    /// for ⌘W, and the app menu for ⌘, and ⌘Q.
    private func setUpMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(item("Open Softly…", #selector(openWindow), key: ","))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Softly", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(item("Quit Softly", #selector(quit), key: "q"))
        main.addItem(submenu(app, title: "Softly"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        main.addItem(submenu(edit, title: "Edit"))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(window, title: "Window"))

        NSApp.mainMenu = main
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        let status = NSMenuItem(title: state.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        // The menu bar menu doesn't take focus, so these paste into the app
        // you were in, the same way a dictation does.
        if !engine.recent.isEmpty {
            let recent = NSMenu()
            for text in engine.recent {
                let short = text.count > 60 ? String(text.prefix(57)) + "…" : text
                let entry = item(short, #selector(pasteRecent(_:)))
                entry.representedObject = text
                entry.toolTip = text
                recent.addItem(entry)
            }
            menu.addItem(submenu(recent, title: "Paste Recent Dictation"))
            menu.addItem(.separator())
        }

        menu.addItem(item("Open Softly…", #selector(openWindow), key: ","))
        if case .available(let version) = state.update {
            menu.addItem(item("Update to Softly \(version)…", #selector(installUpdate)))
        } else {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(item("Preview Pill", #selector(previewPill)))
        let sounds = item("Play Sounds", #selector(toggleSounds))
        sounds.state = state.soundsEnabled ? .on : .off
        menu.addItem(sounds)
        menu.addItem(.separator())

        if engine.modelStatus != .ready {
            if engine.modelStatus == .missingModel {
                menu.addItem(item("Download Speech Model (\(SpeechModel.current.sizeMB) MB)", #selector(downloadModel)))
            }
            menu.addItem(item("Show Model Folder", #selector(showModelFolder)))
            menu.addItem(item("Reload Model", #selector(reloadModel)))
        }
        if !hotkeys.isRunning {
            menu.addItem(item("Open Input Monitoring Settings…", #selector(openInputMonitoring)))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibility)))
        }
        if !Permissions.microphoneGranted {
            menu.addItem(item("Open Microphone Settings…", #selector(openMicrophone)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Softly", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openWindow() { mainWindow.show() }
    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        // Wait for the menu to close and focus to settle back on the app.
        after(0.15) { Paster.paste(text) }
    }
    @objc private func previewPill() { engine.preview() }
    @objc private func checkForUpdates() { updater.check(); mainWindow.show() }
    @objc private func installUpdate() { updater.install() }
    @objc private func toggleSounds() { state.soundsEnabled.toggle() }
    @objc private func reloadModel() { engine.loadModel() }
    @objc private func downloadModel() { downloader.start(SpeechModel.current); mainWindow.show() }
    @objc private func openInputMonitoring() { Permissions.openSettings("Privacy_ListenEvent") }
    @objc private func openAccessibility() { Permissions.openSettings("Privacy_Accessibility") }
    @objc private func openMicrophone() { Permissions.openSettings("Privacy_Microphone") }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showModelFolder() {
        try? FileManager.default.createDirectory(at: Settings.modelDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Settings.modelDirectory)
    }
}
