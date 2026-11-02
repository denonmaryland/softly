import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Themes.js" as Themes

// Softly settings: the Linux counterpart of the Mac app's window,
// in Omarchy's own idiom (a bar icon and a popover). Sounds and fixes live
// in ~/.config/omarchy/softly.json, read live by Service.qml and by
// ~/.local/bin/softly-fix; the vocabulary is Voxtype's
// whisper.initial_prompt and the speech model its whisper.model, both
// written through helpers/control.py, which restarts the daemon.
Panel {
  id: root
  moduleName: "io.github.denonmaryland.softly"
  ipcTarget: "io.github.denonmaryland.softly.settings"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^(file|qs):\/\//, "")).replace(/\/$/, "")
  readonly property string helper: pluginDir + "/helpers/control.py"

  property bool loaded: false
  property bool sounds: true
  property string pillTheme: "omarchy"
  property bool tapToStart: true
  property bool submitWord: false
  // The pill follows Omarchy by default; the fixed styles are for the Mac and
  // Windows apps mostly, so the grid stays folded away until asked for.
  property bool stylesOpen: false
  readonly property string pillThemeName: Themes.named(pillTheme).name
  property var vocabulary: []
  property string service: "unknown"
  property string daemon: "unknown"
  property string model: ""
  property string speechModel: ""  // fast | balanced | accurate, "" for a model Softly did not pick
  property var models: []          // [{id, name, detail, sizeMB, downloaded}]
  property var download: null      // {id, phase, progress, error} while a model downloads
  property var fixes: []           // [{from, to}]
  property string language: "en"
  property var languages: []       // [{code, name}]
  property bool langsOpen: false
  // "main" (status, model, switches, recent), "words" or "settings"
  property string page: "main"
  // The settings page is short enough to show its key and language choices unfolded.
  onPageChanged: if (page === "settings") { keysOpen = true; langsOpen = true }
  readonly property string languageName: (languages.find(l => l.code === language) || { name: language }).name
  property string heardDraft: ""
  property string typedDraft: ""
  property var recent: []       // [{text, at}], newest first
  property string version: ""
  property var setup: null      // {paste, voxtype, hypr, complete, hotkey, voxtypeInstalled}
  readonly property string hotkey: String(setting("hotkey", "F9") || "F9")
  // Hyprland key names read badly in sentences; name the common modifiers.
  readonly property string hotkeyLabel: ({ "Alt_R": "Right Alt", "Alt_L": "Left Alt", "Super_R": "Right Super", "Control_R": "Right Ctrl", "Shift_R": "Right Shift" })[hotkey] || hotkey
  // Keys that work on their own; any other Hyprland key name can still be set
  // with `omarchy bar set io.github.denonmaryland.softly hotkey <key>`.
  readonly property var hotkeyChoices: [
    { id: "F9", label: "F9" }, { id: "Alt_R", label: "Right Alt" }, { id: "Control_R", label: "Right Ctrl" }, { id: "Super_R", label: "Right Super" },
    { id: "F8", label: "F8" }, { id: "F10", label: "F10" }, { id: "F11", label: "F11" }, { id: "F12", label: "F12" }
  ]
  property bool keysOpen: false
  readonly property bool setUp: !!(setup && setup.complete)
  property var update: null     // {current, latest, available, url} or {error}
  property bool checkingUpdate: false
  property string message: ""
  property var pending: []     // helper commands waiting their turn
  property string draft: ""
  // Keyboard rows: 0 sounds · 1 tap to start · 2 dictation key · 3 pill style (Enter opens, left/right picks) · 4 add field · 5 preview · 6+ words.
  property int cursor: 0
  readonly property int wordRow0: 6
  readonly property int rowCount: wordRow0 + vocabulary.length

  readonly property bool busy: readProc.running || writeProc.running || pending.length > 0
  readonly property string statusText: setup && !setup.complete ? "Not set up on this machine yet"
    : service !== "active" ? "Voxtype is not running"
    : daemon === "recording" || daemon === "streaming" ? "Recording…"
    : daemon === "transcribing" ? "Transcribing…"
    : daemon === "idle" ? (tapToStart ? "Ready · tap " + hotkeyLabel + " to start, tap again to finish" : "Ready · hold " + hotkeyLabel + " while you talk") : "Starting…"

  function alphaOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function refresh() { if (!busy) readProc.running = true }
  function receive(text) {
    try {
      const s = JSON.parse(text)
      loaded = true
      sounds = s.sounds !== false
      pillTheme = s.pillTheme || "omarchy"
      tapToStart = s.tapToStart !== false
      submitWord = s.submitWord === true
      vocabulary = s.vocabulary || []
      service = s.service || "unknown"
      daemon = s.daemon || "unknown"
      model = s.model || ""
      speechModel = s.speechModel || ""
      models = s.models || []
      download = s.download || null
      fixes = s.replacements || []
      language = s.language || "en"
      languages = s.languages || []
      recent = s.recent || []
      version = s.version || ""
      setup = s.setup || null
      if (s.update) { update = s.update; checkingUpdate = false }
      if (s.errors && s.errors.length) message = s.errors.join("\n")
      else if (message.indexOf("Saving") === 0) message = "Saved · Voxtype restarted"
      else if (message.indexOf("Setting up") === 0) message = setup && setup.complete ? "Set up · hold " + hotkey + " to dictate" : "Setup did not finish"
      else if (message.indexOf("Removing") === 0) message = "Softly's setup was removed"
      else if (message.indexOf("Switching model") === 0 || message.indexOf("Switching language") === 0) message = download ? "" : "Saved · Voxtype restarted"
      else if (message.indexOf("Switching") === 0) message = ""
    } catch (e) { message = "Could not read dictation settings." }
  }
  function send(args) { pending = pending.concat([args]); drain() }
  function drain() {
    if (writeProc.running || readProc.running || !pending.length) return
    const args = pending[0]
    pending = pending.slice(1)
    writeProc.command = ["/usr/bin/python", helper].concat(args)
    writeProc.running = true
  }
  function setSounds(on) {
    sounds = on
    message = ""
    send(["set", "sounds", on ? "true" : "false"])
  }
  function setTap(on) {
    tapToStart = on
    message = ""
    send(["set", "tap", on ? "true" : "false"])
  }
  function setSubmit(on) {
    submitWord = on
    message = ""
    send(["set", "submit", on ? "true" : "false"])
  }
  function setTheme(id) {
    if (id === pillTheme) return
    pillTheme = id
    message = ""
    send(["set", "theme", id])
    // Service.qml picks the file up live; show it on screen straight away.
    previewDelay.restart()
  }
  function setHotkey(id) {
    if (id === hotkey) return
    message = setUp ? "Switching to " + (({ "Alt_R": "Right Alt", "Super_R": "Right Super", "Control_R": "Right Ctrl" })[id] || id) + "…" : ""
    send(["hotkey", id])
  }
  function stepHotkey(dx) {
    let i = 0
    for (let k = 0; k < hotkeyChoices.length; k++) if (hotkeyChoices[k].id === hotkey) i = k
    setHotkey(hotkeyChoices[(i + dx + hotkeyChoices.length) % hotkeyChoices.length].id)
  }
  function stepTheme(dx) {
    let i = 0
    for (let k = 0; k < Themes.list.length; k++) if (Themes.list[k].id === pillTheme) i = k
    setTheme(Themes.list[(i + dx + Themes.list.length) % Themes.list.length].id)
  }
  Timer { id: previewDelay; interval: 250; onTriggered: root.preview() }
  function addWord() {
    const w = draft.trim()
    if (!w) return
    wordField.text = ""
    draft = ""
    message = "Saving and restarting Voxtype…"
    send(["add", w])
  }
  function removeWord(w) {
    message = "Saving and restarting Voxtype…"
    send(["remove", w])
  }
  function chooseModel(id) {
    if (id === speechModel && !download) return
    const m = models.find(x => x.id === id)
    message = m && m.downloaded ? "Switching model and restarting Voxtype…" : ""
    send(["model", id])
  }
  function chooseLanguage(code) {
    if (code === language) return
    language = code
    message = "Switching language and restarting Voxtype…"
    send(["language", code])
  }
  function cancelDownload() { download = null; send(["cancel-download"]) }
  function addFix() {
    const heard = heardDraft.trim()
    if (!heard) return
    const typed = typedDraft.trim()
    heardField.text = ""; typedField.text = ""
    heardDraft = ""; typedDraft = ""
    message = ""
    send(["fix-add", heard, typed])
  }
  function removeFix(heard) { message = ""; send(["fix-remove", heard]) }
  function preview() { Quickshell.execDetached(["omarchy-shell", "io.github.denonmaryland.softly", "preview"]) }
  function copyText(t) { Quickshell.execDetached(["wl-copy", "--", t]); message = "Copied" }
  function clearRecent() { recent = []; send(["clear-recent"]) }
  function runSetup() { message = "Setting up… Voxtype restarts and Hyprland reloads."; send(["setup", hotkey]) }
  function removeSetup() { message = "Removing Softly's setup…"; send(["teardown"]) }
  function checkUpdate() { checkingUpdate = true; update = null; send(["check-update"]) }
  function installUpdate() { message = "Updating with omarchy plugin update…"; send(["update"]) }
  readonly property string updateLabel: checkingUpdate ? "Checking…"
    : !update ? "Check for updates"
    : update.error ? "Try again"
    : update.available ? "Update to " + update.latest
    : "Up to date"
  function ago(at) {
    const s = Math.max(0, Math.floor(Date.now() / 1000 - at))
    return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + " min ago" : s < 86400 ? Math.floor(s / 3600) + " h ago" : "earlier"
  }
  function activate() {
    if (cursor === 0) setSounds(!sounds)
    else if (cursor === 1) setTap(!tapToStart)
    else if (cursor === 2) keysOpen = !keysOpen
    else if (cursor === 3) stylesOpen = !stylesOpen
    else if (cursor === 4) wordField.forceActiveFocus()
    else if (cursor === 5) preview()
    else if (cursor - wordRow0 < vocabulary.length) removeWord(vocabulary[cursor - wordRow0])
  }
  onRowCountChanged: if (cursor >= rowCount) cursor = Math.max(0, rowCount - 1)
  Component.onCompleted: refresh()
  onOpenedChanged: {
    if (opened) { message = ""; refresh(); poll.restart() }
    else { poll.stop(); stylesOpen = false; keysOpen = false; langsOpen = false; page = "main"; keyboard.forceActiveFocus() }
  }

  // Daemon state changes outside this panel; keep the status line honest while it is open.
  Timer { id: poll; interval: 2000; repeat: true; onTriggered: root.refresh() }

  IpcHandler {
    target: "io.github.denonmaryland.softly.settings"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens on a page: main, words or settings.
    function show(name: string): void { root.page = name; root.open() }
    function state(): string {
      return JSON.stringify({loaded: root.loaded, hotkey: root.hotkey, keysOpen: root.keysOpen, sounds: root.sounds, tapToStart: root.tapToStart, pillTheme: root.pillTheme, vocabulary: root.vocabulary,
                             service: root.service, daemon: root.daemon, model: root.model, message: root.message})
    }
  }
  Process {
    id: readProc
    command: ["/usr/bin/python", root.helper, "state"]
    stdout: StdioCollector { onStreamFinished: root.receive(text) }
    onExited: Qt.callLater(root.drain)
  }
  Process {
    id: writeProc
    stdout: StdioCollector { onStreamFinished: root.receive(text) }
    onExited: function(code, status) {
      if (code !== 0 && root.message.indexOf("Could not") < 0) root.message = "Could not save. Reopen this panel to retry."
      Qt.callLater(root.drain)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍬"
    tooltipText: "Softly · sounds, vocabulary & status"
    onPressed: if (!(root.popup && root.popup.commitHover(root))) root.toggle()
  }

  // The popup host is Omarchy's stock card, or the frosted host from the
  // denon.bar plugin when that is installed. The content is reparented into
  // whichever loads (hosts/*.qml).
  property bool hostChosen: false
  property bool useGlassHost: false
  readonly property var popup: hostLoader.item
  readonly property Item keyboardItem: keyboard
  readonly property real contentImplicitHeight: content.implicitHeight
  FileView {
    path: root.pluginDir + "/../denon.bar/panels/PopupPanel.qml"
    printErrors: false
    onLoaded: { root.useGlassHost = true; root.hostChosen = true }
    onLoadFailed: root.hostChosen = true
  }
  onHostChosenChanged: hostLoader.setSource(useGlassHost ? "hosts/GlassHost.qml" : "hosts/StockHost.qml",
                                            { softly: root, anchorItem: button, bar: root.bar })
  Loader { id: hostLoader }
  Item { id: parking; visible: false; width: Style.space(340); height: Style.space(700) }

    PanelKeyCatcher {
      id: keyboard
      parent: root.popup ? root.popup.slot : parking
      anchors.fill: parent
      blocked: wordField.activeFocus || heardField.activeFocus || typedField.activeFocus
      onCloseRequested: if (root.page !== "main") root.page = "main"; else root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy) root.cursor = Math.max(0, Math.min(root.rowCount - 1, root.cursor + dy))
        else if (dx && root.cursor === 3 && root.stylesOpen) root.stepTheme(dx)
        else if (dx && root.cursor === 2 && root.keysOpen) root.stepHotkey(dx)
      }
      onActivateRequested: root.activate()

      // The popover is capped at the screen's height; the rest scrolls.
      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

      Column {
        id: content
        width: scroller.width
        spacing: Style.space(12)

        // ---------- Sub-page title, with the way back ----------
        Column {
          visible: root.page !== "main"
          width: parent.width
          spacing: Style.space(3)
          Text {
            text: "‹ Softly"
            color: root.accent
            font.family: root.family; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold
            MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.page = "main" }
          }
          Text {
            text: root.page === "words" ? "Words" : "Key, language & pill"
            color: root.fg; font.family: root.family; font.pixelSize: Style.font.title; font.bold: true
          }
        }

        // ---------- Header: title and live status ----------
        Column {
          visible: root.page === "main"
          width: parent.width
          spacing: Style.space(3)
          Text {
            text: "Softly"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Row {
            spacing: Style.space(7)
            Rectangle {
              width: Style.space(7); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.service !== "active" ? root.alphaOf(root.fg, 0.35)
                   : root.daemon === "idle" ? root.accent : root.fg
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.loaded ? root.statusText : "Checking…"
              color: root.fg
              opacity: 0.75
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }


        // ---------- Set up: three writes, each with consent and a backup ----------
        Column {
          visible: (root.page === "main") && (root.loaded && root.setup && (!root.setup.complete || (root.setup.hotkey && root.setup.hotkey !== root.hotkey)))
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: root.setUp ? "NEW KEY" : "SET UP"
            color: root.fg; opacity: 0.6
            font.family: root.family; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.setUp
              ? "The dictation key in Softly's settings is " + root.hotkey + ", but Hyprland is set up for " + root.setup.hotkey + "."
              : "Softly writes three things on this machine, each backed up first: the paste helper to ~/.local/bin, Voxtype's output settings (clipboard through that helper, its own overlay off), and ~/.config/hypr/softly.lua for the " + root.hotkey + " key, loaded by one marked line at the end of hyprland.lua. Remove it any time from this panel."
            color: root.fg; opacity: 0.7
            font.family: root.family; font.pixelSize: Style.font.caption
          }
          Column {
            visible: !root.setUp
            spacing: Style.space(2)
            Repeater {
              model: [["paste", "Paste helper"], ["voxtype", "Voxtype output"], ["hypr", "Hyprland key"]]
              delegate: Text {
                required property var modelData
                text: (root.setup && root.setup[modelData[0]] ? "󰄬  " : "○  ") + modelData[1]
                color: root.fg; opacity: root.setup && root.setup[modelData[0]] ? 0.9 : 0.55
                font.family: root.family; font.pixelSize: Style.font.caption
              }
            }
          }
          Text {
            visible: root.setup && !root.setup.voxtypeInstalled
            width: parent.width; wrapMode: Text.WordWrap
            text: "Voxtype is not installed. It ships with Omarchy; install it first, then set up Softly."
            color: root.fg; opacity: 0.8
            font.family: root.family; font.pixelSize: Style.font.caption
          }
          Button {
            text: root.setUp ? "Apply " + root.hotkey : "Set up Softly"
            foreground: root.fg
            fontFamily: root.family
            bordered: true
            active: true
            enabled: !root.busy && root.setup && root.setup.voxtypeInstalled
            onClicked: root.runSetup()
          }
        }

        PanelSeparator { visible: (root.page === "main") && (root.loaded && root.setup && !root.setup.complete); foreground: root.fg }


        // ---------- Speech model: three sizes of the same engine ----------
        Column {
          visible: root.page === "main"
          width: parent.width
          spacing: Style.space(8)
          Column {
            width: parent.width
            spacing: Style.space(2)
            Item {
              width: parent.width
              height: modelTitle.implicitHeight
              Text { id: modelTitle; text: "Model"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: Font.DemiBold }
              Text {
                anchors.right: parent.right; anchors.baseline: modelTitle.baseline
                text: root.speechModel === "parakeet" ? "Detects language" : root.languageName
                color: root.fg; opacity: langLinkMouse.containsMouse ? 0.9 : 0.55
                font.family: root.family; font.pixelSize: Style.font.caption
                MouseArea { id: langLinkMouse; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.page = "settings" }
              }
            }
            // Only when there is something to say: a failure, a model Softly
            // did not pick, or Parakeet's missing vocabulary hints.
            Text {
              readonly property string note: root.download && root.download.phase === "failed" ? "Download failed · " + (root.download.error || "try again")
                : root.speechModel === "" && root.model ? root.model.replace(/^ggml-/, "").replace(/\.bin$/, "") + " · set in Voxtype"
                : root.speechModel === "parakeet" ? "Vocabulary hints don't apply to Parakeet; fixes do."
                : ""
              visible: note.length > 0
              width: parent.width; wrapMode: Text.WordWrap
              text: note
              color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption
            }
          }
          Row {
            id: modelChips
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: Math.floor((width - (root.models.length - 1) * spacing) / Math.max(1, root.models.length))
            Repeater {
              model: root.models
              delegate: Rectangle {
                id: mchip
                required property var modelData
                readonly property bool selected: modelData.id === root.speechModel
                readonly property bool fetching: !!(root.download && root.download.id === modelData.id && root.download.phase !== "failed")
                width: modelChips.cell; height: Style.space(42); radius: Style.space(8)
                color: root.alphaOf(root.fg, mchipMouse.containsMouse ? 0.1 : 0.05)
                border.width: selected ? 2 : 1
                border.color: selected ? root.accent : root.alphaOf(root.fg, 0.14)
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(1)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mchip.modelData.name
                    color: root.fg
                    opacity: mchip.selected ? 1 : 0.8
                    font.family: root.family; font.pixelSize: Style.font.caption
                    font.weight: mchip.selected ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mchip.fetching ? (root.download.phase === "verifying" ? "Verifying…" : Math.round((root.download.progress || 0) * 100) + "% · cancel")
                      : mchip.selected ? "In use"
                      : mchip.modelData.downloaded ? "Ready"
                      : mchip.modelData.sizeMB + " MB"
                    color: root.fg
                    opacity: 0.5
                    font.family: root.family; font.pixelSize: Style.font.caption - 1
                  }
                }
                MouseArea {
                  id: mchipMouse
                  anchors.fill: parent
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  enabled: root.loaded && !root.busy
                  onClicked: mchip.fetching ? root.cancelDownload() : root.chooseModel(mchip.modelData.id)
                }
              }
            }
          }
        }


        SwitchRow {
          visible: root.page === "main"
          width: parent.width
          title: "Play sounds"
          caption: "A subtle cue when recording starts and ends"
          checked: root.sounds
          focusRing: root.cursor === 0
          onToggled: root.setSounds(!root.sounds)
          onHoveredIn: root.cursor = 0
        }


        SwitchRow {
          visible: root.page === "main"
          width: parent.width
          title: "Tap to start and stop"
          caption: root.tapToStart ? "Tap once, talk, tap again to finish. Holding still works." : "Off: hold " + root.hotkeyLabel + " while you talk, let go to finish"
          checked: root.tapToStart
          focusRing: root.cursor === 1
          onToggled: root.setTap(!root.tapToStart)
          onHoveredIn: root.cursor = 1
        }


        SwitchRow {
          visible: root.page === "main"
          width: parent.width
          title: "Say “submit” to send"
          caption: "End with “submit” and Softly presses Enter after pasting"
          checked: root.submitWord
          enabled: !root.busy
          onToggled: root.setSubmit(!root.submitWord)
        }


        // ---------- Recent dictations (runtime only; gone at logout) ----------
        Column {
          visible: root.page === "main"
          width: parent.width
          spacing: Style.space(8)
          Item {
            width: parent.width
            height: recentHead.implicitHeight
            Text {
              id: recentHead
              text: "RECENT"
              color: root.fg
              opacity: 0.6
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }
            Text {
              anchors.right: parent.right
              visible: root.recent.length > 0
              text: "Clear"
              color: root.fg
              opacity: clearMouse.containsMouse ? 0.9 : 0.5
              font.family: root.family
              font.pixelSize: Style.font.caption
              MouseArea { id: clearMouse; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearRecent() }
            }
          }
          Text {
            visible: root.loaded && root.recent.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Nothing dictated yet this session. The last few transcripts show here so you can copy them again."
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.recent
            delegate: Item {
              required property var modelData
              required property int index
              width: content.width
              height: entry.implicitHeight + Style.space(index === 0 ? 10 : 6)
              Column {
                id: entry
                anchors.left: parent.left
                anchors.right: copyButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: modelData.text
                  color: root.fg
                  opacity: index === 0 ? 1 : 0.8
                  wrapMode: index === 0 ? Text.WordWrap : Text.NoWrap
                  elide: Text.ElideRight
                  maximumLineCount: index === 0 ? 4 : 1
                  font.family: root.family
                  font.pixelSize: index === 0 ? Style.font.body : Style.font.caption
                }
                Text {
                  visible: index === 0
                  text: root.ago(modelData.at)
                  color: root.fg
                  opacity: 0.5
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }
              PanelActionButton {
                id: copyButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰆏"
                tooltipText: "Copy"
                foreground: root.fg
                fontFamily: root.family
                fontSize: Style.font.caption
                onClicked: root.copyText(modelData.text)
              }
            }
          }
        }


        // ---------- The two sub-pages ----------
        Column {
          visible: root.page === "main"
          width: parent.width
          LinkRow { width: parent.width; title: "Words & fixes"; detail: String(root.vocabulary.length + root.fixes.length); onClicked: root.page = "words" }
          LinkRow { width: parent.width; title: "Key, language & pill"; detail: root.hotkeyLabel + " · " + root.languageName; onClicked: root.page = "settings" }
        }

        Item {
          visible: root.page === "main"
          width: parent.width
          height: Math.max(versionText.implicitHeight, updateButton.implicitHeight)
          Text {
            id: versionText
            anchors.left: parent.left
            anchors.right: updateButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: "Softly " + root.version + (root.model ? " · " + root.model.replace(/^ggml-/, "").replace(/\.bin$/, "") + " · local" : "")
                  + (root.update && root.update.error ? " · " + root.update.error : "")
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
          Button {
            id: updateButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.updateLabel
            foreground: root.fg
            fontFamily: root.family
            fontSize: Style.font.caption
            bordered: true
            active: !!(root.update && root.update.available)
            enabled: !root.checkingUpdate && !root.busy
            onClicked: root.update && root.update.available ? root.installUpdate() : root.checkUpdate()
          }
        }

        // ---------- Dictation key: a short list that works on its own ----------
        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(8)
          Item {
            width: parent.width
            height: keyText.implicitHeight
            Column {
              id: keyText
              width: parent.width - keyLink.implicitWidth - Style.space(12)
              spacing: Style.space(2)
              Text { text: "Dictation key"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: root.cursor === 2 ? Font.DemiBold : Font.Normal }
              Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: root.hotkeyLabel + (root.setUp || !root.setup ? (root.tapToStart ? " · tap or hold it" : " · hold it while you talk") : " · applied when you set up Softly")
                color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption
              }
            }
            Text {
              id: keyLink
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              text: root.keysOpen ? "Done" : "Change"
              color: root.fg
              opacity: keyMouse.containsMouse || root.cursor === 2 ? 0.9 : 0.5
              font.family: root.family; font.pixelSize: Style.font.caption
              MouseArea {
                id: keyMouse
                anchors.fill: parent; anchors.margins: -Style.space(4)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                enabled: root.loaded
                onEntered: root.cursor = 2
                onClicked: root.keysOpen = !root.keysOpen
              }
            }
          }
          Flow {
            id: keyChips
            visible: root.keysOpen
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: Math.floor((width - 3 * spacing) / 4)
            Repeater {
              model: root.hotkeyChoices
              delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool selected: modelData.id === root.hotkey
                width: keyChips.cell; height: Style.space(28); radius: Style.space(8)
                color: root.alphaOf(root.fg, chipMouse.containsMouse ? 0.1 : 0.05)
                border.width: selected ? 2 : 1
                border.color: selected ? root.accent : root.alphaOf(root.fg, 0.14)
                Text {
                  anchors.centerIn: parent
                  text: chip.modelData.label
                  color: root.fg
                  opacity: chip.selected ? 1 : 0.75
                  font.family: root.family; font.pixelSize: Style.font.caption
                  font.weight: chip.selected ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  enabled: !root.busy
                  onEntered: root.cursor = 2
                  onClicked: root.setHotkey(chip.modelData.id)
                }
              }
            }
          }
        }


        // ---------- Language: English, detect, or one of the common ones ----------
        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(8)
          Item {
            width: parent.width
            height: langText.implicitHeight
            Column {
              id: langText
              width: parent.width - langLink.implicitWidth - Style.space(12)
              spacing: Style.space(2)
              Text { text: "Language"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body }
              Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: root.speechModel === "parakeet" ? "Parakeet detects the language itself"
                  : root.languageName + (root.language === "en" ? "" : " · uses the multilingual model")
                color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption
              }
            }
            Text {
              id: langLink
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              text: root.langsOpen ? "Done" : "Change"
              color: root.fg
              opacity: langMouse.containsMouse ? 0.9 : 0.5
              font.family: root.family; font.pixelSize: Style.font.caption
              MouseArea {
                id: langMouse
                anchors.fill: parent; anchors.margins: -Style.space(4)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                enabled: root.loaded
                onClicked: root.langsOpen = !root.langsOpen
              }
            }
          }
          Flow {
            id: langChips
            visible: root.langsOpen
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: Math.floor((width - 2 * spacing) / 3)
            Repeater {
              model: root.languages
              delegate: Rectangle {
                id: lchip
                required property var modelData
                readonly property bool selected: modelData.code === root.language
                width: modelData.code === "auto" ? langChips.cell * 2 + langChips.spacing : langChips.cell
                height: Style.space(28); radius: Style.space(8)
                color: root.alphaOf(root.fg, lchipMouse.containsMouse ? 0.1 : 0.05)
                border.width: selected ? 2 : 1
                border.color: selected ? root.accent : root.alphaOf(root.fg, 0.14)
                Text {
                  anchors.centerIn: parent
                  text: lchip.modelData.name
                  color: root.fg
                  opacity: lchip.selected ? 1 : 0.75
                  font.family: root.family; font.pixelSize: Style.font.caption
                  font.weight: lchip.selected ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                  id: lchipMouse
                  anchors.fill: parent
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  enabled: !root.busy
                  onClicked: root.chooseLanguage(lchip.modelData.code)
                }
              }
            }
          }
        }


        // ---------- Pill style: Omarchy's theme or a fixed look ----------
        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(8)
          Item {
            width: parent.width
            height: styleText.implicitHeight
            Column {
              id: styleText
              width: parent.width - styleLink.implicitWidth - Style.space(12)
              spacing: Style.space(2)
              Text { text: "Pill style"; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: root.cursor === 3 ? Font.DemiBold : Font.Normal }
              Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: root.pillTheme === "omarchy" ? "Follows your Omarchy theme" : root.pillThemeName + " · a fixed look, whatever the theme"
                color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption
              }
            }
            Text {
              id: styleLink
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              text: root.stylesOpen ? "Done" : "Change"
              color: root.fg
              opacity: styleMouse.containsMouse || root.cursor === 3 ? 0.9 : 0.5
              font.family: root.family; font.pixelSize: Style.font.caption
              MouseArea {
                id: styleMouse
                anchors.fill: parent; anchors.margins: -Style.space(4)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                enabled: root.loaded
                onEntered: root.cursor = 3
                onClicked: root.stylesOpen = !root.stylesOpen
              }
            }
          }
          Flow {
            id: swatches
            visible: root.stylesOpen
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: Math.floor((width - 3 * spacing) / 4)
            Repeater {
              model: Themes.list
              delegate: Item {
                id: swatch
                required property var modelData
                readonly property bool selected: modelData.id === root.pillTheme
                readonly property color bg: modelData.background || Color.background
                readonly property color ink: modelData.foreground || Color.foreground
                readonly property color glow: modelData.accent || Color.accent
                readonly property bool light: bg.hslLightness > 0.5
                width: swatches.cell
                height: swatchColumn.implicitHeight
                Column {
                  id: swatchColumn
                  width: parent.width
                  spacing: Style.space(4)
                  Rectangle {
                    width: parent.width; height: Style.space(26); radius: Style.space(8)
                    color: "transparent"
                    border.width: swatch.selected || (root.cursor === 3 && swatchMouse.containsMouse) ? 2 : 0
                    border.color: swatch.selected ? root.accent : root.alphaOf(root.fg, 0.4)
                    Rectangle {
                      id: cap
                      anchors.centerIn: parent
                      width: parent.width - Style.space(8); height: Style.space(18); radius: height / 2
                      border.width: 1
                      border.color: Qt.rgba(0, 0, 0, swatch.light ? 0.12 : 0.4)
                      gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(swatch.bg, swatch.light ? 1.03 : 1.13) }
                        GradientStop { position: 1; color: Qt.darker(swatch.bg, 1.1) }
                      }
                      Rectangle {
                        x: 3; y: 3; width: parent.width - 16; height: parent.height - 6; radius: height / 2
                        color: swatch.light ? Qt.darker(swatch.bg, 1.12) : Qt.darker(swatch.bg, 1.5)
                        Rectangle {
                          anchors.fill: parent; radius: height / 2
                          gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(swatch.glow, 0) }
                            GradientStop { position: 0.5; color: Qt.alpha(swatch.glow, 0.55) }
                            GradientStop { position: 1; color: Qt.alpha(swatch.glow, 0) }
                          }
                        }
                        Row {
                          anchors.centerIn: parent
                          spacing: 2
                          Repeater {
                            model: [3, 6, 9, 5, 7, 4]
                            delegate: Rectangle {
                              required property var modelData
                              anchors.verticalCenter: parent.verticalCenter
                              width: 1.5; height: modelData; radius: 0.75
                              color: swatch.ink
                            }
                          }
                        }
                      }
                      Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 3; radius: 1.5
                        color: Qt.alpha(swatch.ink, 0.76)
                      }
                    }
                  }
                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: swatch.modelData.name
                    color: root.fg
                    opacity: swatch.selected ? 0.95 : 0.6
                    font.family: root.family; font.pixelSize: Style.font.caption
                    font.weight: swatch.selected ? Font.DemiBold : Font.Normal
                  }
                }
                MouseArea {
                  id: swatchMouse
                  anchors.fill: parent
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  enabled: root.loaded
                  onEntered: root.cursor = 3
                  onClicked: root.setTheme(swatch.modelData.id)
                }
              }
            }
          }
        }


        // ---------- Footer: preview and model ----------
        Button {
          visible: root.page === "settings"
          text: "Preview pill"
          foreground: root.fg
          fontFamily: root.family
          bordered: true
          hasCursor: root.cursor === 5
          enabled: root.service === "active" && root.daemon === "idle"
          onClicked: root.preview()
          onHovered: function(h) { if (h) root.cursor = 5 }
        }

        Text {
          visible: (root.page === "settings") && (root.setUp)
          text: "Remove Softly's setup from this machine"
          color: root.fg
          opacity: removeMouse.containsMouse ? 0.9 : 0.45
          font.family: root.family
          font.pixelSize: Style.font.caption
          MouseArea { id: removeMouse; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeSetup() }
        }

        // ---------- Vocabulary ----------
        Column {
          visible: root.page === "words"
          width: parent.width
          spacing: Style.space(3)
          Text {
            text: "VOCABULARY"
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Names Softly gets wrong. Saved to Voxtype on this machine; the daemon restarts after each change."
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          visible: root.page === "words"
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: wordField
            width: parent.width - addButton.width - parent.spacing
            foreground: root.fg
            placeholderText: "Add a word or name"
            hasCursor: root.cursor === 4 && !activeFocus
            onTextChanged: root.draft = text
            onAccepted: root.addWord()
            onActiveFocusChanged: if (activeFocus) root.cursor = 4
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { keyboard.forceActiveFocus(); event.accepted = true }
            }
          }
          Button {
            id: addButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Add"
            foreground: root.fg
            fontFamily: root.family
            bordered: true
            enabled: root.draft.trim().length > 0 && !root.busy
            onClicked: root.addWord()
          }
        }

        // Vocabulary as chips; × removes one.
        Flow {
          visible: root.page === "words" && root.vocabulary.length > 0
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.vocabulary
            delegate: Rectangle {
              id: chip
              required property string modelData
              width: chipRow.implicitWidth + Style.space(18); height: Style.space(26); radius: height / 2
              color: root.alphaOf(root.fg, chipX.containsMouse ? 0.12 : 0.07)
              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Style.space(6)
                Text { text: chip.modelData; color: root.fg; font.family: root.family; font.pixelSize: Style.font.caption + 1; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: "×"; color: root.fg; opacity: chipX.containsMouse ? 0.9 : 0.45
                  font.family: root.family; font.pixelSize: Style.font.caption + 1; anchors.verticalCenter: parent.verticalCenter
                  MouseArea { id: chipX; anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.busy; onClicked: root.removeWord(chip.modelData) }
                }
              }
            }
          }
        }

        Text {
          visible: (root.page === "words") && (root.loaded && root.vocabulary.length === 0)
          text: "No words yet. Softly uses its defaults."
          color: root.fg
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
        }


        PanelSeparator { visible: root.page === "words"; foreground: root.fg }


        // ---------- Fixes: "when Softly hears this, type that" ----------
        Column {
          visible: root.page === "words"
          width: parent.width
          spacing: Style.space(3)
          Text {
            text: "FIXES"
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "When Softly hears the left side, it types the right. Leave the right empty to drop a word, like “um”. Applied straight away."
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          visible: root.page === "words"
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: heardField
            width: (parent.width - fixAddButton.width - arrowText.width - 3 * parent.spacing) / 2
            foreground: root.fg
            placeholderText: "Heard"
            onTextChanged: root.heardDraft = text
            onAccepted: typedField.forceActiveFocus()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { keyboard.forceActiveFocus(); event.accepted = true }
            }
          }
          Text {
            id: arrowText
            anchors.verticalCenter: parent.verticalCenter
            text: "→"
            color: root.fg; opacity: 0.5
            font.family: root.family; font.pixelSize: Style.font.body
          }
          TextField {
            id: typedField
            width: heardField.width
            foreground: root.fg
            placeholderText: "Type"
            onTextChanged: root.typedDraft = text
            onAccepted: root.addFix()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { keyboard.forceActiveFocus(); event.accepted = true }
            }
          }
          Button {
            id: fixAddButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Add"
            foreground: root.fg
            fontFamily: root.family
            bordered: true
            enabled: root.heardDraft.trim().length > 0 && !root.busy
            onClicked: root.addFix()
          }
        }

        Column {
          visible: root.page === "words"
          width: parent.width
          spacing: 0
          Repeater {
            model: root.fixes
            delegate: Item {
              required property var modelData
              width: content.width
              height: Style.space(20)
              Text {
                anchors.left: parent.left
                anchors.right: fixRemove.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: parent.modelData.from + "  →  " + (parent.modelData.to || "(removed)")
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
              }
              PanelActionButton {
                id: fixRemove
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                tooltipText: "Remove"
                foreground: root.fg
                fontFamily: root.family
                fontSize: Style.font.caption
                enabled: !root.busy
                onClicked: root.removeFix(parent.modelData.from)
              }
            }
          }
        }

        Text {
          visible: (root.page === "words") && (root.loaded && root.fixes.length === 0)
          text: "No fixes yet."
          color: root.fg
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
        }


        Text {
          visible: root.message.length > 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.message
          color: root.fg
          opacity: 0.75
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

      }
      }
    }

  // A row that opens a sub-page: title on the left, a count or summary and › on the right.
  component LinkRow: Item {
    id: link
    property string title: ""
    property string detail: ""
    signal clicked()
    height: Style.space(40)
    Rectangle { width: parent.width; height: 1; color: root.alphaOf(root.fg, 0.12) }
    Text {
      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
      text: link.title
      color: root.fg; font.family: root.family; font.pixelSize: Style.font.body
    }
    Text {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      text: link.detail + "  ›"
      color: root.fg; opacity: linkMouse.containsMouse ? 0.9 : 0.55
      font.family: root.family; font.pixelSize: Style.font.caption
    }
    MouseArea { id: linkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.clicked() }
  }

  component Switch: Rectangle {
    id: sw
    property bool checked: false
    property bool focusRing: false
    signal toggled()
    signal hoveredIn()
    width: Style.space(32); height: Style.space(18); radius: height / 2
    color: checked ? root.accent : root.alphaOf(root.fg, 0.16)
    border.width: focusRing ? 2 : 0
    border.color: root.alphaOf(root.fg, 0.7)
    opacity: enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle {
      width: parent.height - Style.space(4); height: width; radius: width / 2
      y: Style.space(2)
      x: sw.checked ? parent.width - width - Style.space(2) : Style.space(2)
      color: "white"
      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      anchors.fill: parent; anchors.margins: -Style.space(5)
      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      enabled: sw.enabled && root.loaded
      onClicked: sw.toggled()
      onEntered: sw.hoveredIn()
    }
  }

  component SwitchRow: Item {
    id: row
    property string title: ""
    property string caption: ""
    property bool checked: false
    property bool focusRing: false
    signal toggled()
    signal hoveredIn()
    height: Math.max(rowText.implicitHeight, rowSwitch.height)
    Column {
      id: rowText
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - rowSwitch.width - Style.space(12)
      spacing: Style.space(2)
      Text { text: row.title; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: row.focusRing ? Font.DemiBold : Font.Normal }
      Text { width: parent.width; wrapMode: Text.WordWrap; text: row.caption; color: root.alphaOf(root.fg, 0.5); font.family: root.family; font.pixelSize: Style.font.caption }
    }
    Switch {
      id: rowSwitch
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      checked: row.checked
      enabled: row.enabled
      focusRing: row.focusRing
      onToggled: row.toggled()
      onHoveredIn: row.hoveredIn()
    }
  }
}
