// Pure key gesture state machine; the QML adapter owns processes.
//  Tap the key  -> start hands-free; tap again to finish.
//  Hold the key -> record while held, transcribe on release.
//  tapToStart false -> hold-only: release always finishes.
var HOLD_MS = 500;

function createController() {
    return {
        tapToStart: true,
        held: false, locked: false, owned: false,
        ignoreRelease: false, pressedAt: 0,
        send: function(event, now, daemon) {
            var recording = daemon === "recording" || daemon === "streaming";
            if (event === "reset") {
                this.locked = this.owned = false;
                this.ignoreRelease = this.held;
                return [];
            }
            if (event === "stop" || event === "cancel") {
                this.locked = this.owned = false;
                this.ignoreRelease = this.held;
                return [event];
            }
            if (event === "toggle") {
                if (this.owned || recording) return this.send("stop", now, daemon);
                if (daemon !== "idle") return [];
                this.owned = this.locked = true;
                return ["start"];
            }
            if (event === "press") {
                if (this.held) return [];
                this.held = true;
                this.pressedAt = now;
                if (this.locked || (!this.owned && recording)) {
                    this.ignoreRelease = true;
                    return this.send("stop", now, daemon);
                }
                if (daemon === "idle" && !this.owned) {
                    this.owned = true;
                    return ["start"];
                }
                this.ignoreRelease = true;
                return [];
            }
            if (event === "release") {
                if (!this.held) return [];
                this.held = false;
                if (this.ignoreRelease) { this.ignoreRelease = false; return []; }
                if (this.locked || !this.owned) return [];
                if (this.tapToStart && now - this.pressedAt < HOLD_MS) {
                    this.locked = true;
                    return [];
                }
                this.owned = false;
                return ["stop"];
            }
            return [];
        }
    };
}
