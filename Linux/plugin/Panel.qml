import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Softly settings: the Linux counterpart of the Mac app's window,
// in Omarchy's own idiom (a bar icon and a popover). Sounds live in
// ~/.config/omarchy/softly.json, which Service.qml reads live; the
// vocabulary is Voxtype's whisper.initial_prompt, written through
// helpers/control.py, which restarts the daemon.
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
  property var vocabulary: []
  property string service: "unknown"
  property string daemon: "unknown"
  property string model: ""
  property var recent: []       // [{text, at}], newest first
  property string version: ""
  property var setup: null      // {paste, voxtype, hypr, complete, hotkey, voxtypeInstalled}
  readonly property string hotkey: String(setting("hotkey", "F9") || "F9")
  readonly property bool setUp: !!(setup && setup.complete)
  property var update: null     // {current, latest, available, url} or {error}
  property bool checkingUpdate: false
  property string message: ""
  property var pending: []     // helper commands waiting their turn
  property string draft: ""
  // Keyboard rows: 0 sounds · 1 add field · 2 preview · 3+ words.
  property int cursor: 0
  readonly property int wordRow0: 3
  readonly property int rowCount: wordRow0 + vocabulary.length

  readonly property bool busy: readProc.running || writeProc.running || pending.length > 0
  readonly property string statusText: setup && !setup.complete ? "Not set up on this machine yet"
    : service !== "active" ? "Voxtype is not running"
    : daemon === "recording" || daemon === "streaming" ? "Recording…"
    : daemon === "transcribing" ? "Transcribing…"
    : daemon === "idle" ? "Ready · hold " + hotkey + ", or double-tap for hands-free" : "Starting…"

  function alphaOf(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function refresh() { if (!busy) readProc.running = true }
  function receive(text) {
    try {
      const s = JSON.parse(text)
      loaded = true
      sounds = s.sounds !== false
      vocabulary = s.vocabulary || []
      service = s.service || "unknown"
      daemon = s.daemon || "unknown"
      model = s.model || ""
      recent = s.recent || []
      version = s.version || ""
      setup = s.setup || null
      if (s.update) { update = s.update; checkingUpdate = false }
      if (s.errors && s.errors.length) message = s.errors.join("\n")
      else if (message.indexOf("Saving") === 0) message = "Saved · Voxtype restarted"
      else if (message.indexOf("Setting up") === 0) message = setup && setup.complete ? "Set up · hold " + hotkey + " to dictate" : "Setup did not finish"
      else if (message.indexOf("Removing") === 0) message = "Softly's setup was removed"
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
    else if (cursor === 1) wordField.forceActiveFocus()
    else if (cursor === 2) preview()
    else if (cursor - wordRow0 < vocabulary.length) removeWord(vocabulary[cursor - wordRow0])
  }
  onRowCountChanged: if (cursor >= rowCount) cursor = Math.max(0, rowCount - 1)
  Component.onCompleted: refresh()
  onOpenedChanged: {
    if (opened) { message = ""; refresh(); poll.restart() }
    else { poll.stop(); keyboard.forceActiveFocus() }
  }

  // Daemon state changes outside this panel; keep the status line honest while it is open.
  Timer { id: poll; interval: 2000; repeat: true; onTriggered: root.refresh() }

  IpcHandler {
    target: "io.github.denonmaryland.softly.settings"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function state(): string {
      return JSON.stringify({loaded: root.loaded, sounds: root.sounds, vocabulary: root.vocabulary,
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
      blocked: wordField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy) root.cursor = Math.max(0, Math.min(root.rowCount - 1, root.cursor + dy)) }
      onActivateRequested: root.activate()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        // ---------- Header: title and live status ----------
        Column {
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
          visible: root.loaded && root.setup && (!root.setup.complete || (root.setup.hotkey && root.setup.hotkey !== root.hotkey))
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
            text: "Voxtype is not installed. Run: omarchy pkg add voxtype"
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
        PanelSeparator { visible: root.loaded && root.setup && !root.setup.complete; foreground: root.fg }

        SwitchRow {
          width: parent.width
          title: "Play sounds"
          caption: "A subtle cue when recording starts and ends"
          checked: root.sounds
          focusRing: root.cursor === 0
          onToggled: root.setSounds(!root.sounds)
          onHoveredIn: root.cursor = 0
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Recent dictations (runtime only; gone at logout) ----------
        Column {
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

        PanelSeparator { foreground: root.fg }

        // ---------- Vocabulary ----------
        Column {
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
            text: "Names Whisper gets wrong. Saved to Voxtype on this machine; the daemon restarts after each change."
            color: root.fg
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: wordField
            width: parent.width - addButton.width - parent.spacing
            foreground: root.fg
            placeholderText: "Add a word or name"
            hasCursor: root.cursor === 1 && !activeFocus
            onTextChanged: root.draft = text
            onAccepted: root.addWord()
            onActiveFocusChanged: if (activeFocus) root.cursor = 1
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
        Column {
          width: parent.width
          spacing: 0
          Repeater {
          model: root.vocabulary
          delegate: Item {
            required property string modelData
            required property int index
            width: content.width
            height: Style.space(20)
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.weight: root.cursor === root.wordRow0 + parent.index ? Font.DemiBold : Font.Normal
            }
            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅖"
              tooltipText: "Remove"
              foreground: root.fg
              fontFamily: root.family
              fontSize: Style.font.caption
              hasCursor: root.cursor === root.wordRow0 + parent.index
              enabled: !root.busy
              onClicked: root.removeWord(parent.modelData)
              onHovered: function(h) { if (h) root.cursor = root.wordRow0 + parent.index }
            }
          }
          }
        }
        Text {
          visible: root.loaded && root.vocabulary.length === 0
          text: "No words yet. Whisper uses its defaults."
          color: root.fg
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Footer: preview and model ----------
        Button {
          text: "Preview pill"
          foreground: root.fg
          fontFamily: root.family
          bordered: true
          hasCursor: root.cursor === 2
          enabled: root.service === "active" && root.daemon === "idle"
          onClicked: root.preview()
          onHovered: function(h) { if (h) root.cursor = 2 }
        }
        Item {
          width: parent.width
          height: Math.max(versionText.implicitHeight, updateButton.implicitHeight)
          Text {
            id: versionText
            anchors.left: parent.left
            anchors.right: updateButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: "Softly " + root.version + (root.model ? " · Whisper " + root.model.replace(/^ggml-/, "").replace(/\.bin$/, "") + " · local" : "")
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
        Text {
          visible: root.setUp
          text: "Remove Softly's setup from this machine"
          color: root.fg
          opacity: removeMouse.containsMouse ? 0.9 : 0.45
          font.family: root.family
          font.pixelSize: Style.font.caption
          MouseArea { id: removeMouse; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeSetup() }
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
