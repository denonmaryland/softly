import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import qs.Commons as Commons
import "Controller.js" as Keys

Item {
    id: root
    property var controller: Keys.createController()
    property string daemon: "idle"
    property string displayState: "recording"
    property bool locked: false
    property bool held: false
    property bool waiting: false
    property bool showing: false
    property var selectedScreen: Quickshell.screens[0]
    property var commands: []
    property real rms: 0
    property real envelope: 0
    property var levels: Array(19).fill(0)
    property var shown: Array(19).fill(0)
    property real phase: 0
    property real presence: 0
    property real surfaceOpacity: 0
    property real contentPresence: 0
    // Independent state weights keep waveform, light and labels continuous.
    // While hidden they snap, so a new session never replays the last ending.
    property real processingMix: displayState === "transcribing" ? 1 : 0
    property real completionMix: displayState === "complete" ? 1 : 0
    Behavior on processingMix { enabled: panel.visible; NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
    Behavior on completionMix { enabled: panel.visible; NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
    // Status glyph: three round-capped lines in a 14-unit box; unused lines
    // collapse to the centre so any shape morphs into any other.
    readonly property var glyphShapes: ({
        none: [[7, 7, 7, 7, 0], [7, 7, 7, 7, 0], [7, 7, 7, 7, 0]],
        more: [[2.5, 7, 2.5, 7, 1], [7, 7, 7, 7, 1], [11.5, 7, 11.5, 7, 1]],
        check: [[2.5, 7.5, 5.5, 10.5, 1], [5.5, 10.5, 11.5, 3.5, 1], [7, 7, 7, 7, 0]],
        cross: [[3, 3, 11, 11, 1], [7, 7, 7, 7, 0], [11, 3, 3, 11, 1]]
    })
    component Morph: NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.19, 1, 0.22, 1, 1, 1] }
    function ramp(a, b, t) {
        const x = Math.max(0, Math.min(1, (t - a) / (b - a)))
        return x * x * (3 - 2 * x)
    }
    property bool outputReady: false
    property bool silentCycle: false
    property bool soundsEnabled: true
    // Shared with the bar popover (Panel.qml); edits there apply live.
    readonly property string settingsPath: ((Quickshell.env("XDG_CONFIG_HOME") || "").startsWith("/") ? Quickshell.env("XDG_CONFIG_HOME") : Quickshell.env("HOME") + "/.config") + "/omarchy/softly.json"
    function applySettings(text) {
        try { root.soundsEnabled = JSON.parse(text).sounds !== false } catch (e) {}
    }
    FileView {
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.applySettings(text())
        onFileChanged: reload()
    }
    // The surface leads the content. All animations resume from their current
    // values if dismissed/reopened; never reset an in-flight reveal to zero.
    // System feedback uses bounded easing, without overshoot or text squashing.
    onShowingChanged: {
        if (showing) {
            departure.stop()
            arrival.restart()
            if (!silentCycle) playCue("open")
        } else {
            arrival.stop()
            departure.restart()
            if (!silentCycle) playCue("close")
        }
    }
    ParallelAnimation {
        id: arrival
        NumberAnimation { target: root; property: "presence"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "surfaceOpacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            NumberAnimation { target: root; property: "contentPresence"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        }
    }
    // Motion still builds with ease-in; the fades are spread evenly so the
    // surface dissolves instead of popping off in the last frames.
    ParallelAnimation {
        id: departure
        NumberAnimation { target: root; property: "presence"; to: 0; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "surfaceOpacity"; to: 0; duration: 180; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "contentPresence"; to: 0; duration: 110; easing.type: Easing.InOutQuad }
    }
    function playCue(which) {
        if (!soundsEnabled || cue.running) return
        cue.command = ["pw-play", Qt.resolvedUrl("sounds/" + which + ".wav").toString().replace("file://", "")]
        cue.running = true
    }
    Process { id: cue }
    Timer {
        id: idleSettle; interval: 75
        onTriggered: {
            if (root.outputReady) {
                root.displayState = "complete"
                completionHold.restart()
            } else root.showing = false
        }
    }
    Timer { id: completionHold; interval: 450; onTriggered: root.showing = false }
    property double startedAt: 0
    property int elapsed: 0
    property bool previewing: false
    readonly property bool recording: daemon === "recording" || daemon === "streaming"
    readonly property color background: Commons.Color.background
    readonly property color foreground: Commons.Color.foreground
    readonly property color accent: Commons.Color.accent
    readonly property bool lightTheme: background.hslLightness > 0.5
    // Backlit groove: the accent glow under the waveform replaces the old status dot.
    readonly property real glowTarget: displayState === "transcribing" ? 0 : (displayState === "complete" ? 0.55 : 1)
    property real glow: glowTarget
    Behavior on glow { enabled: panel.visible; NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
    readonly property color floor: lightTheme ? Qt.darker(background, 1.12) : Qt.darker(background, 1.5)
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") + "/voxtype"

    function selectScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        for (let s of Quickshell.screens) if (s.name === name) { selectedScreen = s; return }
        selectedScreen = Quickshell.screens[0]
    }
    function handle(event) {
        const actions = controller.send(event, Date.now(), daemon)
        locked = controller.locked
        held = controller.held
        waiting = controller.waiting
        for (let action of actions) {
            if (action === "timer-start") releaseTimer.restart()
            else if (action === "timer-stop") releaseTimer.stop()
            else { commands = commands.concat([action]); nextCommand() }
        }
    }
    function nextCommand() {
        if (worker.running || !commands.length) return
        const action = commands[0]
        commands = commands.slice(1)
        worker.command = ["voxtype", "record", action]
        worker.running = true
    }
    function updateState(next) {
        const previous = daemon
        daemon = next
        if (next !== "idle") {
            if (previewing) stopPreview()
            displayState = next
            if (previous === "idle") { silentCycle = false; selectScreen(); startedAt = Date.now(); elapsed = 0; envelope = 0; levels = Array(19).fill(0); shown = Array(19).fill(0); outputReady = false; idleSettle.stop(); completionHold.stop() }
            showing = true
        } else if (!previewing && showing) idleSettle.restart()
        if (next === "idle" || next === "transcribing") {
            rms = 0
            handle("reset")
        }
    }
    Process {
        id: worker
        onExited: (code, status) => {
            if (code !== 0) { root.handle("reset"); console.warn("Softly: Voxtype command failed", code) }
            Qt.callLater(root.nextCommand)
        }
    }
    Timer { id: releaseTimer; interval: 330; onTriggered: root.handle("timeout") }
    FileView {
        path: root.runtime + "/state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.updateState(text().trim() || "idle")
        onLoadFailed: root.updateState("idle")
    }
    Process {
        id: audio
        command: ["voxtype-audio-bridge"]
        running: root.recording
        stdout: SplitParser {
            onRead: data => {
                try {
                    const frame = JSON.parse(data)
                    if (typeof frame.rms === "number") root.rms = Math.max(0, Math.min(1, frame.rms))
                } catch (e) {}
            }
        }
        onExited: { root.rms = 0; if (root.recording) reconnect.restart() }
    }
    Timer { id: reconnect; interval: 1000; onTriggered: { if (root.recording) audio.running = true } }
    Timer {
        interval: 40; repeat: true; running: root.showing
        onTriggered: {
            // Preview fakes a speech-like level so the look can be checked without the mic.
            if (root.previewing) root.rms = 0.004 + 0.09 * Math.pow(Math.abs(Math.sin(root.phase * 3.1) * Math.sin(root.phase * 0.7 + 0.6)), 1.2) * Math.random()
            // RMS-driven, compressed and smoothed; never changes capture gain.
            const target = Math.min(1, Math.sqrt(root.rms) * 2.2)
            root.envelope += (target - root.envelope) * (target > root.envelope ? 0.5 : 0.2)
            const live = root.displayState === "transcribing" ? 0 : root.envelope * (0.55 + 0.45 * Math.random())
            root.levels = [live].concat(root.levels.slice(0, root.levels.length - 1))
            if (root.recording || root.previewing) root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
        }
    }
    FrameAnimation {
        running: panel.visible
        onTriggered: {
            root.phase += frameTime
            const k = 1 - Math.exp(-frameTime * 22)
            root.shown = root.shown.map((v, i) => v + (root.levels[i] - v) * k)
        }
    }

    function clock(s) { return Math.floor(s / 60) + ":" + (s % 60).toString().padStart(2, "0") }
    function stopPreview() {
        previewExpiry.stop(); previewProcessing.stop(); previewComplete.stop()
        previewing = false; rms = 0
    }
    function cancelNow() {
        root.outputReady = false; completionHold.stop(); idleSettle.stop()
        if (root.previewing) { root.stopPreview(); root.showing = false }
        else if (root.daemon === "idle") root.showing = false
        else root.handle("cancel")
    }

    IpcHandler {
        target: "denon.softly"
        function press(): void { root.handle("press") }
        function release(): void { root.handle("release") }
        function toggle(): void { root.handle("toggle") }
        function cancel(): void { root.cancelNow() }
        // Called only after the output helper has retained a new clipboard transcript.
        function complete(): void {
            if (root.previewing || !root.showing) return
            root.outputReady = true
            if (root.daemon === "idle") idleSettle.restart()
        }
        // Silent simulated cycle: never activates the microphone or inserts text.
        function preview(): void {
            if (root.daemon !== "idle") return
            root.silentCycle = true; root.previewing = true; root.selectScreen(); root.displayState = "preview"
            root.startedAt = Date.now(); root.elapsed = 0; root.envelope = 0
            root.levels = Array(19).fill(0); root.shown = Array(19).fill(0)
            root.showing = true; previewExpiry.restart(); previewProcessing.restart(); previewComplete.restart()
        }
        function inspect(): string {
            return JSON.stringify({daemon: root.daemon, locked: root.locked, held: root.held,
                showing: root.showing, displayState: root.displayState, presence: root.presence,
                surfaceOpacity: root.surfaceOpacity, contentPresence: root.contentPresence,
                processingMix: root.processingMix, completionMix: root.completionMix, glyph: glyph.shape,
                previewing: root.previewing, panelVisible: panel.visible, soundsEnabled: root.soundsEnabled, elapsed: root.elapsed, rms: root.rms,
                background: root.background.toString(), accent: root.accent.toString()})
        }
    }
    Timer { id: previewProcessing; interval: 3200; onTriggered: { if (root.previewing) root.displayState = "transcribing" } }
    Timer { id: previewComplete; interval: 4600; onTriggered: { if (root.previewing) root.displayState = "complete" } }
    Timer { id: previewExpiry; interval: 5200; onTriggered: { root.rms = 0; if (root.daemon === "idle") root.showing = false; root.previewing = false } }
    PanelWindow {
        id: panel
        screen: root.selectedScreen
        visible: root.showing || departure.running || root.presence > 0.002
        anchors { bottom: true }
        margins { bottom: 14 }
        implicitWidth: 189
        implicitHeight: 64
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "denon-softly"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: clockArea }
        Item {
            id: motionSurface
            width: 189; height: 64
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 4 * (1 - root.presence)
            // Composite in a padded item to keep the original capsule size
            // and all shadows while applying opacity once to the whole surface.
            opacity: root.surfaceOpacity
            layer.enabled: true
            layer.smooth: true
            transform: Scale {
                origin.x: 94.5; origin.y: 32
                xScale: 0.96 + 0.04 * root.presence
                yScale: xScale
            }
            Item {
                id: pebble
                width: 153; height: 32.3
                anchors.centerIn: parent
                // Lifted: a tight contact shadow plus a soft ambient one.
                RectangularShadow {
                    anchors.fill: parent
                    offset: Qt.vector2d(0, 7)
                    radius: 16.15; blur: 15; spread: -5
                    color: Qt.rgba(0, 0, 0, root.lightTheme ? 0.18 : 0.6)
                }
                RectangularShadow {
                    anchors.fill: parent
                    offset: Qt.vector2d(0, 1)
                    radius: 16.15; blur: 1.5
                    color: Qt.rgba(0, 0, 0, root.lightTheme ? 0.14 : 0.4)
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -1
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, root.lightTheme ? 0.14 : 0.55)
                }
                // Lit chamfer: the dark lower lip and lit upper lip peek out 1 px around the face.
                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: Qt.tint(Qt.darker(root.background, 1.1), Qt.rgba(0, 0, 0, root.lightTheme ? 0.12 : 0.45))
                }
                Rectangle {
                    width: parent.width; height: parent.height - 1; radius: height / 2
                    color: Qt.tint(Qt.lighter(root.background, 1.13), Qt.rgba(1, 0.98, 0.92, root.lightTheme ? 0.6 : 0.18))
                }
                Rectangle {
                    y: 1; width: parent.width; height: parent.height - 2; radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(root.background, root.lightTheme ? 1.03 : 1.13) }
                        GradientStop { position: 0.5; color: root.background }
                        GradientStop { position: 1; color: Qt.darker(root.background, 1.1) }
                    }
                }
                Item {
                    id: groove
                    opacity: root.contentPresence
                    x: 5.25; width: 107; height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    // Lower lip catches the backlight; the upper edge falls into shadow.
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: Qt.tint(root.floor, Qt.alpha(root.accent, 0.12 + 0.1 * root.glow))
                    }
                    Rectangle {
                        width: parent.width; height: parent.height - 1; radius: height / 2
                        color: Qt.darker(root.floor, root.lightTheme ? 1.15 : 1.6)
                    }
                    Rectangle {
                        id: grooveFloor
                        y: 1.25; width: parent.width; height: parent.height - 2.25; radius: height / 2
                        color: root.floor
                    }
                    Rectangle {
                        anchors.fill: grooveFloor; radius: height / 2
                        opacity: root.glow * (0.82 + 0.18 * root.envelope)
                        // The backlight blooms from the centre as the content arrives.
                        transform: Scale {
                            origin.x: grooveFloor.width / 2
                            xScale: 0.55 + 0.45 * root.contentPresence
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(root.accent, 0) }
                            GradientStop { position: 0.22; color: Qt.alpha(root.accent, 0.08) }
                            GradientStop { position: 0.5; color: Qt.alpha(root.accent, 0.3) }
                            GradientStop { position: 0.78; color: Qt.alpha(root.accent, 0.08) }
                            GradientStop { position: 1; color: Qt.alpha(root.accent, 0) }
                        }
                    }
                    // Inner shadow under the top edge keeps the glow low in the cut.
                    Rectangle {
                        anchors.fill: grooveFloor; radius: height / 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.alpha(Qt.darker(root.floor, 1.4), 0.8) }
                            GradientStop { position: 0.45; color: Qt.alpha(root.floor, 0) }
                        }
                    }
                    Repeater {
                        model: 19
                        Rectangle {
                            required property int index
                            readonly property real fromCentre: Math.abs(index - 9) / 9
                            readonly property real taper: 1 - 0.65 * fromCentre
                            // Centre-out reveal: the outermost bar trails by ~60 ms (≈7 ms per step).
                            readonly property real reveal: Math.max(0, Math.min(1, (root.contentPresence - 0.35 * fromCentre) / 0.65))
                            readonly property real liveActivity: (root.shown[index] || 0) * taper
                            readonly property real processingActivity: 0.15 + 0.32 * (0.5 + 0.5 * Math.sin(root.phase * 6 - index * 0.55))
                            readonly property real activity: (liveActivity * (1 - root.processingMix)
                                + processingActivity * root.processingMix) * (1 - root.completionMix)
                            readonly property real home: 8 + index * 4.917
                            // On completion the waveform gathers into the centre dot.
                            x: home + (52.25 - home) * root.completionMix; width: 2.5
                            height: 2.5 + Math.min(1, activity) * 13
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1.25
                            color: root.foreground
                            opacity: (0.95 - 0.25 * root.processingMix) * reveal * (1 - root.ramp(0.35, 0.9, root.completionMix))
                        }
                    }
                    Rectangle {
                        opacity: root.ramp(0.3, 0.85, root.completionMix)
                        scale: 0.5 + 0.5 * root.completionMix
                        width: 5; height: 5; radius: 2.5
                        anchors.centerIn: parent
                        color: root.foreground
                    }
                }
                Item {
                    id: clockArea
                    x: 112; width: 41; height: 32.3
                    opacity: root.contentPresence
                    property real hoverMix: clockMouse.containsMouse && root.displayState !== "complete" ? 1 : 0
                    Behavior on hoverMix { enabled: panel.visible; NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
                    // The timer clears before the glyph shows, so text and icon never overlap.
                    readonly property real timerMix: (1 - root.processingMix) * (1 - root.completionMix) * (1 - hoverMix)
                    scale: clockMouse.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent
                        text: root.clock(root.elapsed)
                        color: Qt.alpha(root.foreground, 0.76)
                        font.family: "Adwaita Sans"; font.pixelSize: 11; font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                        opacity: clockArea.timerMix * clockArea.timerMix
                    }
                    // Processing dots stretch into the check, or into × on hover;
                    // exponential ease-out reads as a quick snap with a soft settle.
                    Item {
                        id: glyph
                        readonly property real unit: 0.8
                        readonly property string shape: root.displayState === "complete" ? "check"
                            : clockMouse.containsMouse ? "cross"
                            : root.displayState === "transcribing" ? "more" : "none"
                        width: 14 * unit; height: 14 * unit
                        anchors.centerIn: parent
                        // Composited once so the check's overlapping caps keep even ink.
                        layer.enabled: true
                        layer.smooth: true
                        opacity: (0.76 + 0.24 * clockArea.hoverMix) * Math.max(0, Math.min(1, 1 - 2.5 * clockArea.timerMix))
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                readonly property var target: root.glyphShapes[glyph.shape][index]
                                property real x1: target[0]
                                property real y1: target[1]
                                property real x2: target[2]
                                property real y2: target[3]
                                property real ink: target[4]
                                property real stroke: glyph.shape === "more" ? 2.5 : 1.5
                                Behavior on x1 { enabled: panel.visible; Morph {} }
                                Behavior on y1 { enabled: panel.visible; Morph {} }
                                Behavior on x2 { enabled: panel.visible; Morph {} }
                                Behavior on y2 { enabled: panel.visible; Morph {} }
                                Behavior on ink { enabled: panel.visible; Morph {} }
                                Behavior on stroke { enabled: panel.visible; Morph {} }
                                width: Math.hypot(x2 - x1, y2 - y1) * glyph.unit + stroke
                                height: stroke; radius: stroke / 2
                                x: (x1 + x2) / 2 * glyph.unit - width / 2
                                y: (y1 + y2) / 2 * glyph.unit - height / 2
                                rotation: Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI
                                antialiasing: true
                                opacity: ink
                                color: root.foreground
                            }
                        }
                    }
                    MouseArea {
                        id: clockMouse
                        anchors.fill: parent; hoverEnabled: true
                        enabled: root.showing && root.contentPresence > 0.9
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelNow()
                    }
                }
            }
        }
    }
}
