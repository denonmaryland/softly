// Pure key gesture state machine; the QML adapter owns timers and processes.
function createController() {
    return {
        held: false, locked: false, owned: false, waiting: false,
        ignoreRelease: false, pressedAt: 0, releasedAt: 0,
        send: function(event, now, daemon) {
            var out = [];
            if (event === "reset") {
                this.locked = this.owned = this.waiting = false;
                this.ignoreRelease = this.held;
                out.push("timer-stop");
            } else if (event === "stop" || event === "cancel") {
                this.locked = this.owned = this.waiting = false;
                this.ignoreRelease = this.held;
                out.push("timer-stop", event);
            } else if (event === "toggle") {
                if (this.owned || daemon === "recording" || daemon === "streaming") {
                    return this.send("stop", now, daemon);
                }
                if (daemon !== "idle") return out;
                this.owned = this.locked = true;
                out.push("start");
            } else if (event === "press") {
                if (this.held) return out;
                this.held = true;
                this.pressedAt = now;
                if (this.waiting && now - this.releasedAt <= 330) {
                    this.waiting = false;
                    this.locked = true;
                    out.push("timer-stop");
                } else if (this.locked || (!this.owned && (daemon === "recording" || daemon === "streaming"))) {
                    this.ignoreRelease = true;
                    out = this.send("stop", now, daemon);
                } else if (daemon === "idle" && !this.owned) {
                    this.owned = true;
                    out.push("start");
                } else {
                    this.ignoreRelease = true;
                }
            } else if (event === "release") {
                if (!this.held) return out;
                this.held = false;
                if (this.ignoreRelease) { this.ignoreRelease = false; return out; }
                if (this.locked || !this.owned) return out;
                if (now - this.pressedAt <= 240) {
                    this.waiting = true;
                    this.releasedAt = now;
                    out.push("timer-start");
                } else {
                    this.owned = false;
                    out.push("stop");
                }
            } else if (event === "timeout" && this.waiting) {
                this.waiting = this.owned = false;
                out.push("stop");
            }
            return out;
        }
    };
}
