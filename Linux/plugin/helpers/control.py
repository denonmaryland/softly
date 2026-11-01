#!/usr/bin/env python3
"""Softly settings helper for the bar popover.

    control.py state                 -> JSON snapshot
    control.py set sounds true|false -> ~/.config/omarchy/softly.json
    control.py add <word>            -> Voxtype whisper.initial_prompt, restart daemon
    control.py remove <word>         -> same
    control.py restart               -> restart the Voxtype daemon
    control.py remember <file>       -> keep this transcript in the recent list
    control.py clear-recent          -> forget the recent list
    control.py check-update          -> compare the manifest version with the latest GitHub release
    control.py update                -> install the latest release over this plugin and restart the shell
    control.py setup <key>           -> with the user's consent: paste helper, Voxtype output, Hyprland module
    control.py teardown              -> undo setup (settings and vocabulary stay)

Sounds are read live by Service.qml from softly.json. The vocabulary is
Voxtype's own initial prompt ("A, B, C."), the same format the Mac app uses,
so the two lists can be copied across by hand.
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile


def config_home():
    x = os.environ.get("XDG_CONFIG_HOME", "")
    return x if x.startswith("/") else os.path.expanduser("~/.config")


SETTINGS = os.path.join(config_home(), "omarchy", "softly.json")
# Last few dictations live in the runtime dir (tmpfs): copyable until logout, never on disk.
RECENT = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "softly", "recent.json")
RECENT_MAX = 5


def read_recent():
    try:
        with open(RECENT) as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def write_recent(items):
    os.makedirs(os.path.dirname(RECENT), mode=0o700, exist_ok=True)
    tmp = RECENT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(items[:RECENT_MAX], f)
    os.replace(tmp, RECENT)


def remember(path):
    try:
        with open(path) as f:
            text = f.read().strip()
    except OSError:
        return
    if not text:
        return
    items = [i for i in read_recent() if i.get("text") != text]
    write_recent([{"text": text, "at": int(time.time())}] + items)


PLUGIN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "denonmaryland/softly"
ASSET = "Softly-omarchy.zip"


def plugin_version():
    try:
        with open(os.path.join(PLUGIN_DIR, "manifest.json")) as f:
            return str(json.load(f).get("version", "0"))
    except (OSError, ValueError):
        return "0"


def version_parts(v):
    out = []
    for p in v.split("."):
        digits = "".join(ch for ch in p if ch.isdigit())
        out.append(int(digits) if digits else 0)
    return out


def is_newer(a, b):
    pa, pb = version_parts(a), version_parts(b)
    for i in range(max(len(pa), len(pb))):
        x = pa[i] if i < len(pa) else 0
        y = pb[i] if i < len(pb) else 0
        if x != y:
            return x > y
    return False


def fetch(url, binary=False):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Softly/" + plugin_version() + " (Omarchy)",
        "Accept": "application/octet-stream" if binary else "application/vnd.github+json",
    })
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def latest_release():
    data = json.loads(fetch("https://api.github.com/repos/%s/releases/latest" % REPO))
    tag = str(data.get("tag_name", ""))
    version = tag[1:] if tag.startswith("v") else tag
    url = next((a.get("browser_download_url") for a in data.get("assets", []) if a.get("name") == ASSET), None)
    if not version or not url:
        raise RuntimeError("No Omarchy build in the latest release")
    return version, url


def check_update():
    try:
        latest, url = latest_release()
        return {"current": plugin_version(), "latest": latest, "available": is_newer(latest, plugin_version()), "url": url}
    except Exception as e:  # network, JSON, missing asset
        return {"current": plugin_version(), "error": str(e)}


def update():
    info = check_update()
    if "error" in info:
        return [info["error"]]
    if not info["available"]:
        return []
    try:
        blob = fetch(info["url"], binary=True)
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            names = z.namelist()
            if not any(n.startswith("io.github.denonmaryland.softly/") for n in names):
                return ["The download did not contain the plugin"]
            tmp = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "softly", "update")
            shutil.rmtree(tmp, ignore_errors=True)
            z.extractall(tmp)
        shutil.copytree(os.path.join(tmp, "io.github.denonmaryland.softly"), PLUGIN_DIR, dirs_exist_ok=True)
        if os.path.exists(PASTE_DEST):
            shutil.copyfile(PASTE_SRC, PASTE_DEST)
            os.chmod(PASTE_DEST, 0o755)
        shutil.rmtree(tmp, ignore_errors=True)
    except Exception as e:
        return ["Update failed: " + str(e)]
    # The shell restart replaces this plugin's running copy; detach so it does not wait on us.
    subprocess.Popen(["omarchy", "restart", "shell"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return []


# ---------------------------------------------------------------- set up
# Softly needs three things on a machine; each is written only when the user
# presses Set up, and every file is backed up first (name.bak.<time>-softly).
HYPR_DIR = os.path.join(config_home(), "hypr")
HYPRLAND = os.path.join(HYPR_DIR, "hyprland.lua")
MODULE = os.path.join(HYPR_DIR, "softly.lua")
MARK = "-- Softly (remove via its panel)"
LOADER = ('do local d = debug.getinfo(1, "S").source:match("^@(.*/)") or os.getenv("HOME") .. "/.config/hypr/"; '
          'local p = d .. "softly.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end ' + MARK)
PASTE_SRC = os.path.join(PLUGIN_DIR, "bin", "softly-paste")
PASTE_DEST = os.path.expanduser("~/.local/bin/softly-paste")
VOXTYPE_CONFIG = os.path.join(config_home(), "voxtype", "config.toml")
VOXTYPE_KEYS = {
    "output.mode": "clipboard",
    "output.pre_output_command": PASTE_DEST + " save",
    "output.post_output_command": PASTE_DEST + " paste",
    "osd.enabled": "false",      # the pill replaces Voxtype's overlay
    "hotkey.enabled": "false",   # Hyprland drives it
}
HOTKEY_RE = re.compile(r"^[A-Za-z0-9_]+( *\+ *[A-Za-z0-9_]+)*$")


def backup(path):
    if os.path.exists(path):
        shutil.copy2(path, "%s.bak.%s-softly" % (path, time.strftime("%Y%m%d-%H%M%S")))


def atomic_write(path, text, mode=0o644):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def read_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def module_hotkey():
    m = re.match(r"-- softly-hotkey: (.+)", read_text(MODULE))
    return m.group(1).strip() if m else ""


def render_module(hotkey):
    with open(os.path.join(PLUGIN_DIR, "hypr", "module.lua")) as f:
        text = f.read()
    unbind = 'hl.unbind("F9")  -- Omarchy binds F9 to Voxtype itself' if hotkey.replace(" ", "").upper() == "F9" else "-- (the stock F9 Voxtype binding is left alone)"
    return text.replace("@HOTKEY@", hotkey).replace("@UNBIND@", unbind)


def voxtype_get(key):
    code, out, _ = run(["voxtype", "config", "get", key])
    return out.strip() if code == 0 else None


def setup_state():
    paste_ok = os.path.exists(PASTE_DEST) and read_text(PASTE_DEST) == read_text(PASTE_SRC)
    vox_ok = shutil.which("voxtype") is not None and all(voxtype_get(k) == v for k, v in VOXTYPE_KEYS.items())
    hypr_ok = MARK in read_text(HYPRLAND) and os.path.exists(MODULE)
    return {
        "paste": paste_ok, "voxtype": vox_ok, "hypr": hypr_ok,
        "complete": paste_ok and vox_ok and hypr_ok,
        "hotkey": module_hotkey(),
        "voxtypeInstalled": shutil.which("voxtype") is not None,
    }


def hypr_errors():
    code, out, err = run(["hyprctl", "configerrors"])
    text = (out + "\n" + err).strip()
    return [l for l in text.splitlines() if l.strip() and "no errors" not in l.lower()]


def setup(hotkey):
    hotkey = hotkey.strip()
    if not HOTKEY_RE.match(hotkey):
        return ["Not a usable key name: " + hotkey]
    if shutil.which("voxtype") is None:
        return ["Voxtype is not installed. Run: omarchy pkg add voxtype"]
    if run(["hyprctl", "version"])[0] != 0:
        return ["Hyprland is not running"]
    errors = []
    # 1. The paste helper.
    try:
        os.makedirs(os.path.dirname(PASTE_DEST), exist_ok=True)
        shutil.copyfile(PASTE_SRC, PASTE_DEST)
        os.chmod(PASTE_DEST, 0o755)
    except OSError as e:
        return ["Could not install the paste helper: " + str(e)]
    # 2. Voxtype: clipboard output through the helper, its own overlay and hotkey off.
    backup(VOXTYPE_CONFIG)
    for key, value in VOXTYPE_KEYS.items():
        code, out, err = run(["voxtype", "config", "set", key, value])
        if code != 0:
            errors.append("Voxtype %s: %s" % (key, err or out))
    if errors:
        return errors
    run(["systemctl", "--user", "restart", "voxtype"], timeout=30)
    # 3. Hyprland: the module, loaded by one marked line.
    backup(HYPRLAND)
    try:
        atomic_write(MODULE, render_module(hotkey))
        text = read_text(HYPRLAND)
        if MARK not in text:
            if text and not text.endswith("\n"):
                text += "\n"
            atomic_write(HYPRLAND, text + LOADER + "\n")
    except OSError as e:
        return ["Could not write the Hyprland module: " + str(e)]
    run(["hyprctl", "reload"])
    problems = [l for l in hypr_errors() if "softly" in l.lower()]
    if problems:
        return ["Hyprland rejected the module: " + problems[0]]
    return []


def without_loader(text):
    return "".join(l for l in text.splitlines(True) if MARK not in l)


def teardown():
    errors = []
    text = read_text(HYPRLAND)
    if MARK in text:
        backup(HYPRLAND)
        try:
            atomic_write(HYPRLAND, without_loader(text))
        except OSError as e:
            errors.append("Could not edit hyprland.lua: " + str(e))
    try:
        if os.path.exists(MODULE):
            os.remove(MODULE)
    except OSError as e:
        errors.append(str(e))
    run(["hyprctl", "reload"])
    if shutil.which("voxtype"):
        backup(VOXTYPE_CONFIG)
        for key in VOXTYPE_KEYS:
            run(["voxtype", "config", "unset", key])
        run(["systemctl", "--user", "restart", "voxtype"], timeout=30)
    try:
        if os.path.exists(PASTE_DEST):
            os.remove(PASTE_DEST)
    except OSError as e:
        errors.append(str(e))
    return errors


def read_settings():
    try:
        with open(SETTINGS) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_settings(data):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, SETTINGS)


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except (OSError, subprocess.SubprocessError) as e:
        return 1, "", str(e)


def words_from(prompt):
    return [w.strip() for w in prompt.strip().rstrip(".").split(",") if w.strip()]


def prompt_from(words):
    return ", ".join(words) + "." if words else ""


def current_words():
    code, out, _ = run(["voxtype", "config", "get", "whisper.initial_prompt"])
    return words_from(out) if code == 0 else []


def save_words(words):
    prompt = prompt_from(words)
    if prompt:
        code, out, err = run(["voxtype", "config", "set", "whisper.initial_prompt", prompt])
    else:
        code, out, err = run(["voxtype", "config", "unset", "whisper.initial_prompt"])
    return [] if code == 0 else [err or out or "Could not write the Voxtype config."]


def restart():
    code, _, err = run(["systemctl", "--user", "restart", "voxtype"], timeout=30)
    return [] if code == 0 else [err or "Could not restart Voxtype."]


def state(errors=None):
    settings = read_settings()
    _, active, _ = run(["systemctl", "--user", "is-active", "voxtype"])
    code, daemon, _ = run(["voxtype", "status"])
    _, model, _ = run(["voxtype", "config", "get", "whisper.model"])
    errors = errors or []
    return {
        "ok": not errors,
        "errors": errors,
        "sounds": settings.get("sounds", True) is not False,
        "vocabulary": current_words(),
        "service": active or "unknown",
        "daemon": daemon if code == 0 and daemon else "unknown",
        "model": os.path.basename(model) if model else "",
        "recent": read_recent(),
        "version": plugin_version(),
        "setup": setup_state(),
    }


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "state"
    errors = []
    if cmd == "set" and len(argv) == 4 and argv[2] == "sounds":
        settings = read_settings()
        settings["sounds"] = argv[3].lower() in ("1", "true", "yes", "on")
        write_settings(settings)
    elif cmd == "add" and len(argv) == 3:
        word = argv[2].strip().strip(",.")
        words = current_words()
        if word and all(w.lower() != word.lower() for w in words):
            words.append(word)
            errors = save_words(words) or restart()
    elif cmd == "remove" and len(argv) == 3:
        word = argv[2].strip()
        words = [w for w in current_words() if w.lower() != word.lower()]
        errors = save_words(words) or restart()
    elif cmd == "restart":
        errors = restart()
    elif cmd == "remember" and len(argv) == 3:
        remember(argv[2])
    elif cmd == "clear-recent":
        write_recent([])
    elif cmd == "check-update":
        s = state()
        s["update"] = check_update()
        print(json.dumps(s))
        return 0
    elif cmd == "update":
        errors = update()
    elif cmd == "setup" and len(argv) == 3:
        errors = setup(argv[2])
    elif cmd == "teardown":
        errors = teardown()
    elif cmd != "state":
        errors = ["Unknown command: " + " ".join(argv[1:])]
    print(json.dumps(state(errors)))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
