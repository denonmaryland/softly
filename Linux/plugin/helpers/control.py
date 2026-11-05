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
    control.py hotkey <key>          -> save the dictation key and rewrite the Hyprland module for it
    control.py mode softly|omarchy [key] -> who owns the dictation keys (Omarchy 4.5+ only; softly.json)
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
VOXTYPE_MISSING = ("Voxtype is not installed. Install it first: Install > AI > Dictation on Omarchy 4.0, "
                   "Setup > Defaults > Dictation > Voxtype on Omarchy 4.5.")
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


def module_mode():
    m = re.search(r"^-- softly-mode: (\w+)", read_text(MODULE), re.M)
    return m.group(1) if m else "softly"


# ---------- Omarchy's own dictation (4.5 and newer) ----------
# Omarchy 4.5 runs dictation itself: `omarchy-dictation start|stop|toggle`
# drives the app picked in Setup > Defaults > Dictation (Voxtype or
# Superwhisper), bound to Alt + Space (toggle) and Right Alt (hold), and its
# update keeps F9 / Super + Ctrl + X in bindings.lua for people who dictated
# before. Omarchy 4.0 has none of that and binds F9 / Super + Ctrl + X to
# Voxtype directly. hl.unbind drops every bind made with the same key string
# (spaces and case aside), press and release halves alike, so these are the
# exact strings Omarchy binds them with.
OMARCHY_DICTATION_KEYS = ("ALT + SPACE", "ALT + Alt_R")
OMARCHY_LEGACY_KEYS = ("F9", "SUPER + CTRL + X")
MODES = ("softly", "omarchy")


def omarchy_dictation():
    """True on Omarchy 4.5 and newer, which bind dictation keys of their own."""
    return shutil.which("omarchy-dictation") is not None


def omarchy_dictation_info():
    """None before Omarchy 4.5; else the dictation app Omarchy's keys run."""
    if not omarchy_dictation():
        return None
    code, out, _ = run(["omarchy-default-dictation"])
    backend = out if code == 0 and re.fullmatch(r"[a-z0-9][a-z0-9-]*", out) else ""
    return {"backend": backend, "installed": bool(backend) and shutil.which(backend) is not None}


def dictation_mode():
    """softly (the default): Softly's key drives Voxtype. omarchy: Omarchy's
    own dictation keys do, and Softly binds none; only where Omarchy has them."""
    return "omarchy" if read_settings().get("dictationMode") == "omarchy" and omarchy_dictation() else "softly"


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


def key_id(keys):
    parts = [p.strip().upper() for p in keys.split("+") if p.strip()]
    mods = frozenset("CTRL" if p == "CONTROL" else p for p in parts[:-1])
    return mods, parts[-1] if parts else ""


def softly_keys(hotkey):
    """Softly's own binds, after taking the key from an Omarchy dictation bind."""
    same = [k for k in OMARCHY_LEGACY_KEYS if key_id(k) == key_id(hotkey)]
    lines = ['hl.unbind("%s")  -- Omarchy binds %s to its own dictation' % (same[0], same[0]) if same
             else "-- (Omarchy's F9 and Super + Ctrl + X dictation keys are left alone)"]
    lines.append('o.bind("%s", "Softly: tap or hold to dictate", "omarchy-shell %s press")' % (hotkey, ID))
    lines.append('o.bind("%s", "Softly: release", "omarchy-shell %s release", { release = true })' % (release_keys(hotkey), ID))
    return lines


def render_module(hotkey, mode="softly"):
    with open(os.path.join(PLUGIN_DIR, "hypr", "module.lua")) as f:
        text = f.read()
    if mode == "omarchy":
        summary = "Softly: Omarchy's own dictation keys are in charge; Softly binds none."
        keys = ["-- Omarchy 4.5 binds Alt + Space and Right Alt to the dictation app picked in",
                "-- Setup > Defaults > Dictation; Softly leaves those keys alone. Omarchy 4.0",
                "-- has no o.dictation_installed and no such keys, so Softly keeps %s there." % hotkey,
                "if not o.dictation_installed then"] + ["  " + l for l in softly_keys(hotkey)] + ["end"]
    else:
        summary = "Softly: tap %s to start and again to finish, or hold it to talk." % hotkey
        keys = ["-- Omarchy 4.5 binds Alt + Space and Right Alt to its own dictation, which would",
                "-- start Voxtype a second time; Softly drives Voxtype itself, so it takes them",
                "-- back. Omarchy 4.0 has no o.dictation_installed and skips this.",
                "if o.dictation_installed then"] + ['  hl.unbind("%s")' % k for k in OMARCHY_DICTATION_KEYS] + ["end"] + softly_keys(hotkey)
    return (text.replace("@HOTKEY@", hotkey).replace("@MODE@", mode)
            .replace("@SUMMARY@", summary).replace("@KEYS@", "\n".join(keys)))


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
        "stale": hypr_ok and module_stale(),
        "hotkey": module_hotkey(),
        "mode": module_mode(),
        "voxtypeInstalled": shutil.which("voxtype") is not None,
    }


def module_stale():
    """True when softly.lua differs from what this version writes for its key
    and mode, as after an update (Omarchy 4.5 rules) or a mode switch made
    before Set up. Apply in the panel rewrites it."""
    hotkey = module_hotkey()
    if not HOTKEY_RE.match(hotkey):
        return False
    try:
        return read_text(MODULE) != render_module(hotkey, dictation_mode())
    except OSError:
        return False


def hypr_errors():
    code, out, err = run(["hyprctl", "configerrors"])
    text = (out + "\n" + err).strip()
    return [l for l in text.splitlines() if l.strip() and "no errors" not in l.lower()]


def setup(hotkey):
    hotkey = hotkey.strip()
    if not HOTKEY_RE.match(hotkey):
        return ["Not a usable key name: " + hotkey]
    if shutil.which("voxtype") is None:
        return [VOXTYPE_MISSING]
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
        atomic_write(MODULE, render_module(hotkey, dictation_mode()))
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
    return apply_module(render_module(hotkey, dictation_mode()), "that key")


def apply_module(text, what):
    """Rewrites the Hyprland module and reloads; puts the old one back if Hyprland objects."""
    old = read_text(MODULE)
    try:
        atomic_write(MODULE, text)
    except OSError as e:
        return ["Could not write the Hyprland module: " + str(e)]
    run(["hyprctl", "reload"])
    problems = [l for l in hypr_errors() if "softly" in l.lower()]
    if problems:
        atomic_write(MODULE, old)
        run(["hyprctl", "reload"])
        return ["Hyprland rejected %s: %s" % (what, problems[0])]
    return []


def set_mode(mode, hotkey=""):
    """Softly's key drives Voxtype (softly), or Omarchy 4.5's own dictation
    keys run the app picked in Omarchy (omarchy) and Softly binds none.
    Nothing is registered with Omarchy and Voxtype's settings stay as they are."""
    if mode not in MODES:
        return ["Unknown dictation mode: " + mode]
    if mode == "omarchy" and not omarchy_dictation():
        return ["Omarchy's own dictation keys need Omarchy 4.5 or newer."]
    settings = read_settings()
    previous = settings.get("dictationMode")
    settings["dictationMode"] = mode
    write_settings(settings)
    if not (MARK in read_text(HYPRLAND) and os.path.exists(MODULE)):
        return []  # applied by Set up later
    key = module_hotkey() or hotkey.strip() or "F9"
    if not HOTKEY_RE.match(key):
        return ["Not a usable key name: " + key]
    errors = apply_module(render_module(key, mode), "the change")
    if errors:
        settings = read_settings()
        if previous is None:
            settings.pop("dictationMode", None)
        else:
            settings["dictationMode"] = previous
        write_settings(settings)
    return errors


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
        errors += use_whisper_engine()
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
    # NVIDIA Parakeet through Voxtype's ONNX build: fast, 25 European languages
    # detected on its own, but no vocabulary hints (fixes still apply).
    {"id": "parakeet", "name": "Parakeet", "detail": "Fast on CPU · detects 25 languages · no vocabulary hints",
     "engine": "parakeet", "dir": "parakeet-tdt-0.6b-v3-int8", "sizeMB": 640},
]
# Parakeet needs Voxtype's ONNX binary; this drop-in runs the daemon with it.
ENGINE_DROPIN = os.path.join(config_home(), "systemd", "user", "voxtype.service.d", "30-softly-engine.conf")


def onnx_binary():
    flags = read_text("/proc/cpuinfo")
    name = "voxtype-onnx-avx512" if " avx512f" in flags else "voxtype-onnx-avx2"
    path = os.path.join("/usr/lib/voxtype", name)
    return path if os.path.exists(path) else None
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
    if model.get("engine") == "parakeet":
        return {"file": model["dir"], "sizeMB": model["sizeMB"]}
    language = current_language() if language is None else language
    return model["en"] if language == "en" else model["multi"]


def model_downloaded(model, language=None):
    path = os.path.join(models_dir(), model_file(model, language)["file"])
    if model.get("engine") == "parakeet":
        return os.path.exists(os.path.join(path, "encoder-model.int8.onnx"))
    return os.path.exists(path)
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
DOWNLOAD = os.path.join(os.path.dirname(RECENT), "download.json")


def models_dir():
    x = os.environ.get("XDG_DATA_HOME", "")
    base = x if x.startswith("/") else os.path.expanduser("~/.local/share")
    return os.path.join(base, "voxtype", "models")


def model_by_id(model_id):
    return next((m for m in MODELS if m["id"] == model_id), None)


def current_model_id(model_setting):
    if os.path.exists(ENGINE_DROPIN) and voxtype_get("engine") == "parakeet":
        return "parakeet"
    name = os.path.basename(model_setting or "")
    return next((m["id"] for m in MODELS if "en" in m and name in (m["en"]["file"], m["multi"]["file"])), "")


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
    if model.get("engine") == "parakeet":
        binary = onnx_binary()
        if not binary:
            return ["Voxtype's ONNX build is not installed, so Parakeet can't run here."]
        for key, value in (("parakeet.model", model["dir"]), ("parakeet.model_type", "tdt"), ("engine", "parakeet")):
            # The Whisper build refuses Parakeet keys; the ONNX build writes them.
            code, out, err = run([binary, "config", "set", key, value])
            if code != 0:
                return [err or out or "Could not write the Voxtype config."]
        try:
            os.makedirs(os.path.dirname(ENGINE_DROPIN), exist_ok=True)
            atomic_write(ENGINE_DROPIN, "# Softly: Parakeet needs Voxtype's ONNX build. Removed when a Whisper model is picked.\n"
                                        "[Service]\nExecStart=\nExecStart=%s daemon\n" % binary)
        except OSError as e:
            return ["Could not switch Voxtype's engine: " + str(e)]
        run(["systemctl", "--user", "daemon-reload"])
        return restart()
    errors = use_whisper_engine()
    if errors:
        return errors
    path = os.path.join(models_dir(), model_file(model)["file"])
    code, out, err = run(["voxtype", "config", "set", "whisper.model", path])
    if code != 0:
        return [err or out or "Could not write the Voxtype config."]
    return restart()


def use_whisper_engine():
    """Undoes Parakeet: Whisper engine, and the daemon's own binary again."""
    if os.path.exists(ENGINE_DROPIN):
        try:
            os.remove(ENGINE_DROPIN)
        except OSError as e:
            return ["Could not switch Voxtype's engine: " + str(e)]
        run(["systemctl", "--user", "daemon-reload"])
    if voxtype_get("engine") not in (None, "whisper"):
        code, out, err = run(["voxtype", "config", "set", "engine", "whisper"])
        if code != 0:
            return [err or out or "Could not write the Voxtype config."]
    return []


def choose_model(model_id):
    model = model_by_id(model_id)
    if not model:
        return ["Unknown speech model: " + model_id]
    if model_downloaded(model):
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
    if model.get("engine") == "parakeet":
        # Voxtype's ONNX build fetches and checks its own model files.
        binary = onnx_binary()
        code, out, err = (1, "", "Voxtype's ONNX build is not installed.") if not binary else \
            run([binary, "setup", "--download", "--model", model["dir"], "--quiet", "--no-post-install"], timeout=3600)
        if code != 0 or not model_downloaded(model):
            report("failed", 0, (err or out or "Download failed").strip().splitlines()[-1])
            return
        errors = use_model(model)
        if errors:
            report("failed", 0, errors[0])
        else:
            try:
                os.remove(DOWNLOAD)
            except OSError:
                pass
        return
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
                    "downloaded": model_downloaded(m, language)} for m in MODELS if m.get("engine") != "parakeet" or onnx_binary()],
        "language": language,
        "languages": [{"code": c, "name": n} for c, n in LANGUAGES],
        "download": read_download(),
        "replacements": current_fixes(),
        "recent": read_recent(),
        "version": plugin_version(),
        "setup": setup_state(),
        "dictationMode": dictation_mode(),
        "omarchyDictation": omarchy_dictation_info(),
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
    elif cmd == "mode" and len(argv) in (3, 4):
        errors = set_mode(argv[2], argv[3] if len(argv) == 4 else "")
    elif cmd == "teardown":
        errors = teardown()
    elif cmd != "state":
        errors = ["Unknown command: " + " ".join(argv[1:])]
    print(json.dumps(state(errors)))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
