#!/usr/bin/env python3
"""Softly settings helper for the bar popover.

    control.py state                 -> JSON snapshot
    control.py set sounds true|false -> ~/.config/omarchy/softly.json
    control.py set tap true|false    -> tap to start and stop (false: hold-only), same file
    control.py set submit true|false -> a final spoken "submit" presses Enter, same file
    control.py set theme <id>        -> pill style (see Themes.js), same file
    control.py add <word>            -> Voxtype whisper.initial_prompt, restart daemon
    control.py remove <word>         -> same
    control.py restart               -> restart the Voxtype daemon
    control.py fix-add <heard> [type] -> "heard this, type that" fix (empty type drops it), softly.json
    control.py fix-remove <heard>    -> same
    control.py model <id>            -> speech model fast|balanced|accurate; downloads it first in the background
    control.py cancel-download       -> stop that download
    control.py language <code>       -> Voxtype whisper.language (en, auto, es, ...); other than English
                                        switches to the model's multilingual file, downloading it first
    control.py remember <file>       -> keep this transcript in the recent list
    control.py clear-recent          -> forget the recent list
    control.py check-update          -> compare the manifest version with the latest GitHub release
    control.py update                -> run `omarchy plugin update` when a newer release exists
    control.py setup <key>           -> with the user's consent: paste helper, Voxtype output, Hyprland module
    control.py teardown              -> undo setup (settings and vocabulary stay)

Sounds are read live by Service.qml from softly.json, and so are the fixes,
by ~/.local/bin/softly-fix, Voxtype's post-process command. The vocabulary is
Voxtype's own initial prompt ("A, B, C."), the same format the Mac app uses,
so the two lists can be copied across by hand.
"""
import hashlib
import json
import os
import signal
import re
import shutil
import subprocess
import sys
import time
import urllib.request


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
REPO = "denonmaryland/omarchy-softly"
ID = "io.github.denonmaryland.softly"


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
    if not version:
        raise RuntimeError("No release found")
    return version, str(data.get("html_url", ""))


def check_update():
    try:
        latest, url = latest_release()
        return {"current": plugin_version(), "latest": latest, "available": is_newer(latest, plugin_version()), "url": url}
    except Exception as e:  # network, JSON, missing asset
        return {"current": plugin_version(), "error": str(e)}


def git_managed():
    """True when `omarchy plugin add` installed this folder (it keeps the clone's .git)."""
    return os.path.isdir(os.path.join(PLUGIN_DIR, ".git"))


def update():
    """Pulls the newer release with Omarchy's own plugin updater. Nothing is
    downloaded by this helper; a folder install (deploy.sh) is left alone."""
    info = check_update()
    if "error" in info:
        return [info["error"]]
    if not info["available"]:
        return []
    if not git_managed():
        return ["This copy was installed from a folder; update it from the Softly repo (Linux/deploy.sh)"]
    code, out, err = run(["omarchy", "plugin", "update", ID, "--yes"], timeout=120)
    if code != 0:
        return ["omarchy plugin update failed: " + (err or out or str(code))]
    if os.path.exists(PASTE_DEST):
        shutil.copyfile(PASTE_SRC, PASTE_DEST)
        os.chmod(PASTE_DEST, 0o755)
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
FIX_SRC = os.path.join(PLUGIN_DIR, "bin", "softly-fix")
FIX_DEST = os.path.expanduser("~/.local/bin/softly-fix")
VOXTYPE_CONFIG = os.path.join(config_home(), "voxtype", "config.toml")
VOXTYPE_KEYS = {
    "output.mode": "clipboard",
    "output.pre_output_command": PASTE_DEST + " save",
    "output.post_output_command": PASTE_DEST + " paste",
    "output.post_process.command": FIX_DEST,
    "output.post_process.fallback_on_empty": "false",  # all filler, or just "submit": type nothing
    # Transcribe while you talk, cutting at pauses about every 15 s like the Mac and Windows apps.
    "whisper.eager_processing": "true",
    "whisper.eager_chunk_secs": "15.0",
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


# A modifier pressed on its own (Right Alt, say) is still held when Hyprland
# matches its release, so the release bind needs the modifier in front.
MODIFIER_KEYS = {"alt": "ALT", "super": "SUPER", "control": "CTRL", "shift": "SHIFT", "meta": "ALT"}


def release_keys(hotkey):
    parts = [p.strip() for p in hotkey.split("+")]
    key = parts[-1]
    m = re.fullmatch(r"(alt|super|control|shift|meta)_[lr]", key.lower())
    if m and MODIFIER_KEYS[m.group(1)] not in [p.upper() for p in parts[:-1]]:
        parts.insert(len(parts) - 1, MODIFIER_KEYS[m.group(1)])
    return " + ".join(parts)


def render_module(hotkey):
    with open(os.path.join(PLUGIN_DIR, "hypr", "module.lua")) as f:
        text = f.read()
    unbind = 'hl.unbind("F9")  -- Omarchy binds F9 to Voxtype itself' if hotkey.replace(" ", "").upper() == "F9" else "-- (the stock F9 Voxtype binding is left alone)"
    return text.replace("@RELEASE@", release_keys(hotkey)).replace("@HOTKEY@", hotkey).replace("@UNBIND@", unbind)


def voxtype_get(key):
    code, out, _ = run(["voxtype", "config", "get", key])
    return out.strip() if code == 0 else None


def setup_state():
    paste_ok = all(os.path.exists(d) and read_text(d) == read_text(s) for s, d in ((PASTE_SRC, PASTE_DEST), (FIX_SRC, FIX_DEST)))
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
        return ["Voxtype is not installed. It ships with Omarchy; install it first."]
    if run(["hyprctl", "version"])[0] != 0:
        return ["Hyprland is not running"]
    errors = []
    # 1. The paste and fix helpers.
    try:
        os.makedirs(os.path.dirname(PASTE_DEST), exist_ok=True)
        for src, dest in ((PASTE_SRC, PASTE_DEST), (FIX_SRC, FIX_DEST)):
            shutil.copyfile(src, dest)
            os.chmod(dest, 0o755)
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


def set_hotkey(hotkey):
    """Saves the key in the widget's settings and, once Softly is set up,
    rewrites its Hyprland module for it. Voxtype is left alone."""
    hotkey = hotkey.strip()
    if not HOTKEY_RE.match(hotkey):
        return ["Not a usable key name: " + hotkey]
    code, out, err = run(["omarchy", "bar", "set", ID, "hotkey", hotkey], timeout=15)
    if code != 0:
        return ["Could not save the key: " + (err or out).strip()]
    if not (MARK in read_text(HYPRLAND) and os.path.exists(MODULE)):
        return []  # applied by Set up later
    old = read_text(MODULE)
    try:
        atomic_write(MODULE, render_module(hotkey))
    except OSError as e:
        return ["Could not write the Hyprland module: " + str(e)]
    run(["hyprctl", "reload"])
    problems = [l for l in hypr_errors() if "softly" in l.lower()]
    if problems:
        atomic_write(MODULE, old)
        run(["hyprctl", "reload"])
        return ["Hyprland rejected that key: " + problems[0]]
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
    for dest in (PASTE_DEST, FIX_DEST):
        try:
            if os.path.exists(dest):
                os.remove(dest)
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


# ---------- "Heard this, type that" fixes ----------

def current_fixes():
    rules = read_settings().get("replacements", [])
    if not isinstance(rules, list):
        return []
    return [{"from": str(r.get("from", "")), "to": str(r.get("to", ""))} for r in rules
            if isinstance(r, dict) and str(r.get("from", "")).strip()]


def save_fixes(rules):
    settings = read_settings()
    settings["replacements"] = rules
    write_settings(settings)


def add_fix(heard, typed):
    heard = " ".join(heard.split())
    if not heard:
        return ["Say what Softly hears first."]
    # A new fix for the same phrase replaces the old one.
    rules = [r for r in current_fixes() if r["from"].lower() != heard.lower()]
    save_fixes(rules + [{"from": heard, "to": typed.strip()}])
    return []


def remove_fix(heard):
    save_fixes([r for r in current_fixes() if r["from"].lower() != heard.strip().lower()])
    return []


# ---------- Speech models ----------
# Same files, ids and checksums as SpeechModel.swift and SpeechModel.cs. They
# go in Voxtype's models folder and whisper.model points at the chosen one.

# Fast and Balanced have an English-only file and a multilingual one.
TURBO = {"file": "ggml-large-v3-turbo-q5_0.bin", "sha256": "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", "sizeMB": 574}
MODELS = [
    {"id": "fast", "name": "Fast", "detail": "Smallest and quickest",
     "en": {"file": "ggml-base.en-q5_1.bin", "sha256": "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", "sizeMB": 60},
     "multi": {"file": "ggml-base-q5_1.bin", "sha256": "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898", "sizeMB": 60}},
    {"id": "balanced", "name": "Balanced", "detail": "The default",
     "en": {"file": "ggml-small.en-q5_1.bin", "sha256": "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30", "sizeMB": 190},
     "multi": {"file": "ggml-small-q5_1.bin", "sha256": "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", "sizeMB": 190}},
    {"id": "accurate", "name": "Accurate", "detail": "Best with names and code", "en": TURBO, "multi": TURBO},
]
# Same list as Languages.swift and Languages.cs.
LANGUAGES = [
    ("en", "English"), ("auto", "Detect automatically"),
    ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
    ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"),
    ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"),
    ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"),
]


def current_language():
    return voxtype_get("whisper.language") or "en"


def model_file(model, language=None):
    """The file a model needs for the language: English-only, or multilingual."""
    language = current_language() if language is None else language
    return model["en"] if language == "en" else model["multi"]
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
DOWNLOAD = os.path.join(os.path.dirname(RECENT), "download.json")


def models_dir():
    x = os.environ.get("XDG_DATA_HOME", "")
    base = x if x.startswith("/") else os.path.expanduser("~/.local/share")
    return os.path.join(base, "voxtype", "models")


def model_by_id(model_id):
    return next((m for m in MODELS if m["id"] == model_id), None)


def current_model_id(model_setting):
    name = os.path.basename(model_setting or "")
    return next((m["id"] for m in MODELS if name in (m["en"]["file"], m["multi"]["file"])), "")


def read_download():
    try:
        with open(DOWNLOAD) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    # A download whose process died (logout, crash) is not still running.
    if data.get("phase") in ("downloading", "verifying"):
        try:
            os.kill(int(data.get("pid", 0)), 0)
        except (OSError, ValueError):
            return None
    return data


def write_download(data):
    os.makedirs(os.path.dirname(DOWNLOAD), mode=0o700, exist_ok=True)
    tmp = DOWNLOAD + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, DOWNLOAD)


def use_model(model):
    path = os.path.join(models_dir(), model_file(model)["file"])
    code, out, err = run(["voxtype", "config", "set", "whisper.model", path])
    if code != 0:
        return [err or out or "Could not write the Voxtype config."]
    return restart()


def choose_model(model_id):
    model = model_by_id(model_id)
    if not model:
        return ["Unknown speech model: " + model_id]
    if os.path.exists(os.path.join(models_dir(), model_file(model)["file"])):
        cancel_download()
        return use_model(model)
    current = read_download()
    if current and current.get("id") == model_id and current.get("phase") in ("downloading", "verifying"):
        return []
    cancel_download()
    # The download outlives this call (the popover waits on it), so it runs on its own.
    child = subprocess.Popen([sys.executable, os.path.abspath(__file__), "download-model", model_id],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    write_download({"id": model_id, "phase": "downloading", "progress": 0, "pid": child.pid})
    return []


def cancel_download():
    current = read_download()
    if current and current.get("phase") in ("downloading", "verifying"):
        try:
            os.kill(int(current.get("pid", 0)), signal.SIGTERM)
        except (OSError, ValueError):
            pass
    try:
        os.remove(DOWNLOAD)
    except OSError:
        pass
    return []


def download_model(model_id):
    """Runs detached: fetch, verify, switch Voxtype over, restart it."""
    model = model_by_id(model_id)
    if not model:
        return
    pid = os.getpid()
    target = model_file(model)
    dest = os.path.join(models_dir(), target["file"])
    part = dest + ".part"

    def report(phase, progress=0.0, error=""):
        write_download({"id": model_id, "phase": phase, "progress": round(progress, 3), "error": error, "pid": pid})

    def stop(*_):
        try:
            os.remove(part)
        except OSError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    report("downloading")
    try:
        os.makedirs(models_dir(), exist_ok=True)
        req = urllib.request.Request(MODEL_URL + target["file"], headers={"User-Agent": "Softly/" + plugin_version() + " (Omarchy)"})
        digest = hashlib.sha256()
        with urllib.request.urlopen(req, timeout=30) as r, open(part, "wb") as f:
            total = int(r.headers.get("Content-Length") or 0)
            done, last = 0, -1
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                step = int(done * 100 / total) if total else 0
                if step != last:
                    last = step
                    report("downloading", done / total if total else 0)
        report("verifying", 1)
        if digest.hexdigest() != target["sha256"]:
            os.remove(part)
            report("failed", 0, "The download did not verify. Try again.")
            return
        os.replace(part, dest)
    except Exception as e:  # network, disk
        try:
            os.remove(part)
        except OSError:
            pass
        report("failed", 0, str(e))
        return
    errors = use_model(model)
    if errors:
        report("failed", 0, errors[0])
    else:
        try:
            os.remove(DOWNLOAD)
        except OSError:
            pass


def set_language(code):
    if code not in [c for c, _ in LANGUAGES]:
        return ["Unknown language: " + code]
    code_, out, err = run(["voxtype", "config", "set", "whisper.language", code])
    if code_ != 0:
        return [err or out or "Could not write the Voxtype config."]
    # Re-pick the current model: English and other languages use different
    # files. One on disk is switched to (and Voxtype restarted) straight away.
    return choose_model(current_model_id(voxtype_get("whisper.model")) or "balanced")


def restart():
    code, _, err = run(["systemctl", "--user", "restart", "voxtype"], timeout=30)
    return [] if code == 0 else [err or "Could not restart Voxtype."]


def state(errors=None):
    settings = read_settings()
    _, active, _ = run(["systemctl", "--user", "is-active", "voxtype"])
    code, daemon, _ = run(["voxtype", "status"])
    _, model, _ = run(["voxtype", "config", "get", "whisper.model"])
    errors = errors or []
    folder = models_dir()
    language = current_language()
    return {
        "ok": not errors,
        "errors": errors,
        "sounds": settings.get("sounds", True) is not False,
        "tapToStart": settings.get("tapToStart", True) is not False,
        "submitWord": settings.get("submitWord") is True,
        "pillTheme": settings.get("pillTheme") if isinstance(settings.get("pillTheme"), str) else "omarchy",
        "vocabulary": current_words(),
        "service": active or "unknown",
        "daemon": daemon if code == 0 and daemon else "unknown",
        "model": os.path.basename(model) if model else "",
        "speechModel": current_model_id(model),
        "models": [{"id": m["id"], "name": m["name"], "detail": m["detail"], "sizeMB": model_file(m, language)["sizeMB"],
                    "downloaded": os.path.exists(os.path.join(folder, model_file(m, language)["file"]))} for m in MODELS],
        "language": language,
        "languages": [{"code": c, "name": n} for c, n in LANGUAGES],
        "download": read_download(),
        "replacements": current_fixes(),
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
    elif cmd == "set" and len(argv) == 4 and argv[2] == "tap":
        settings = read_settings()
        settings["tapToStart"] = argv[3].lower() in ("1", "true", "yes", "on")
        write_settings(settings)
    elif cmd == "set" and len(argv) == 4 and argv[2] == "submit":
        settings = read_settings()
        settings["submitWord"] = argv[3].lower() in ("1", "true", "yes", "on")
        write_settings(settings)
    elif cmd == "set" and len(argv) == 4 and argv[2] == "theme":
        if re.fullmatch(r"[a-z0-9-]{1,32}", argv[3]):
            settings = read_settings()
            settings["pillTheme"] = argv[3]
            write_settings(settings)
        else:
            errors = ["Unknown pill style: " + argv[3]]
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
    elif cmd == "fix-add" and len(argv) in (3, 4):
        errors = add_fix(argv[2], argv[3] if len(argv) == 4 else "")
    elif cmd == "fix-remove" and len(argv) == 3:
        errors = remove_fix(argv[2])
    elif cmd == "model" and len(argv) == 3:
        errors = choose_model(argv[2])
    elif cmd == "language" and len(argv) == 3:
        errors = set_language(argv[2])
    elif cmd == "cancel-download":
        errors = cancel_download()
    elif cmd == "download-model" and len(argv) == 3:
        download_model(argv[2])
        return 0
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
    elif cmd == "hotkey" and len(argv) == 3:
        errors = set_hotkey(argv[2])
    elif cmd == "teardown":
        errors = teardown()
    elif cmd != "state":
        errors = ["Unknown command: " + " ".join(argv[1:])]
    print(json.dumps(state(errors)))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
