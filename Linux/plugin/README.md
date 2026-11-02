<div align="center">

<img src="docs/wordmark.svg" alt="Softly" width="560">

<p><strong>Local Whisper dictation for Omarchy, with a pill that stays out of your way.</strong><br>
Tap a key, speak, tap again, and the words land where your cursor is. Nothing leaves the machine.</p>

<p>
<a href="https://github.com/denonmaryland/omarchy-softly/releases"><img alt="Release" src="https://img.shields.io/github/v/release/denonmaryland/omarchy-softly?style=flat-square&label=release&color=4C8DFF"></a>
<a href="https://omarchyplugins.com/"><img alt="Omarchy plugin" src="https://img.shields.io/badge/omarchy-plugin-4C8DFF?style=flat-square"></a>
<img alt="Runs locally" src="https://img.shields.io/badge/whisper-on%20device-1E2330?style=flat-square">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-1E2330?style=flat-square"></a>
<a href="https://github.com/denonmaryland/softly"><img alt="Also on macOS and Windows" src="https://img.shields.io/badge/also%20on-macOS%20%C2%B7%20Windows-1E2330?style=flat-square"></a>
</p>

<img src="docs/demo-dictation.gif" alt="Hold F9 and speak: the pill appears, the words land in Obsidian; a tap dictates hands-free into another note; the popover shows what was just said" width="880">

</div>

<br>

<table align="center">
<tr>
<td align="center" width="33%"><h3>Tap</h3>Tap <kbd>F9</kbd>. The pill rises from the bottom of the screen with a live waveform and a timer.</td>
<td align="center" width="33%"><h3>Speak</h3>Say it however it comes. One tap and Softly keeps listening hands-free until you tap again; hold the key instead for push-to-talk.</td>
<td align="center" width="33%"><h3>Release</h3>Whisper runs on this machine, the groove dims while it works, and the text is pasted into the app you were in.</td>
</tr>
</table>

<br>

## Why Softly

<table>
<tr>
<td width="50%" valign="top"><strong>A pill, not a panel.</strong><br>One small capsule with a backlit groove. It appears when you press the key and leaves when the words have landed. Esc or the × cancels.</td>
<td width="50%" valign="top"><strong>Private by construction.</strong><br>Voxtype's Whisper model runs on your GPU or CPU. Audio stays in memory, the transcript stays on your clipboard, and the plugin never phones home except when you ask it to check for updates.</td>
</tr>
<tr>
<td width="50%" valign="top"><strong>Pastes like you would.</strong><br>Ctrl+V in normal apps, Shift+Insert in windows tagged as terminals, sent through Hyprland so Electron apps behave too. If a field refuses the paste, the text is still on the clipboard.</td>
<td width="50%" valign="top"><strong>The few settings that matter.</strong><br>Sounds on or off, a vocabulary of names Whisper gets wrong, the last few transcripts with copy buttons, status, and a preview of the pill. All in one popover on the bar.</td>
</tr>
</table>

## It follows your theme

The capsule, the groove's backlight and the bars take their colours from the Omarchy theme, so the pill looks like it was always part of the desktop. Switch themes and it switches with you.

<div align="center">
<img src="docs/pill-themes.gif" alt="The pill under Gallery City 783, Catppuccin Latte, Synthwave 84 and Tokyo Night" width="760">
<br><br>
<img src="docs/pill-strip.png" alt="Five themes, one pill" width="880">
<br><br>
<img src="docs/demo-themes.gif" alt="Catppuccin Latte, Synthwave 84 and Tokyo Night, with a dictation under each" width="880">
</div>

## The popover

Click the microphone in the bar. Everything Softly can be asked lives here, and it works from the keyboard: Up and Down move between rows, Enter activates.

<div align="center">
<img src="preview.png" alt="The popover: sounds, recent transcripts, vocabulary, status, preview, updates" width="880">
</div>

## Install

```bash
omarchy plugin add https://github.com/denonmaryland/omarchy-softly --enable
```

Then click the microphone icon in the bar and press **Set up Softly**. Softly only writes to your system after that press, and it backs every file up first (`name.bak.<time>-softly`). Prefer a different key? Set **Dictation key** in the widget's settings, then press **Apply** in the popover.

<details>
<summary><strong>What Set up writes</strong></summary>
<br>

1. `~/.local/bin/softly-paste`, the app-aware paste helper.
2. Voxtype's output settings in `~/.config/voxtype/config.toml`: clipboard output through that helper, Voxtype's own overlay and hotkey off.
3. `~/.config/hypr/softly.lua` for your dictation key, loaded by one marked line at the end of `~/.config/hypr/hyprland.lua`. With F9 it replaces Omarchy's stock Voxtype binding; other keys leave F9 alone.

</details>

<details>
<summary><strong>Files it touches</strong></summary>
<br>

| Path | Why |
|---|---|
| `~/.config/omarchy/softly.json` | the sounds switch |
| `$XDG_RUNTIME_DIR/softly/` | recent transcripts (tmpfs, gone at logout) and paste state |
| `~/.config/voxtype/config.toml` | output settings, on Set up (backed up) |
| `~/.config/hypr/softly.lua`, one line in `hyprland.lua` | the key binding, on Set up (backed up) |
| `~/.local/bin/softly-paste` | the paste helper, on Set up |

</details>

<details>
<summary><strong>Dependencies</strong></summary>
<br>

All part of a stock Omarchy install: **Voxtype** (the dictation daemon and its Whisper model; the plugin never installs it, only checks that it is there), `wl-clipboard`, `jq`, `hyprctl`, `python3`. No sudo or pkexec is required. The only service it touches is your own user-level `voxtype` service, restarted after a vocabulary change or Set up. Network access happens only when you press **Check for updates**, which reads the latest release tag on GitHub; updates install through `omarchy plugin update`.

</details>

<details>
<summary><strong>Remove</strong></summary>
<br>

In the popover, **Remove Softly's setup from this machine** undoes the three writes above: Voxtype keys go back to their defaults, the Hyprland line and module are removed, the helper is deleted. Then:

```bash
omarchy plugin remove io.github.denonmaryland.softly
```

Your vocabulary stays in Voxtype's config. The sounds setting lives in `~/.config/omarchy/softly.json` and can be deleted.

</details>

## Same pill, other desks

Softly also runs on **macOS** and **Windows**, with the same pill and the same gesture rules. Both live in the [Softly repo](https://github.com/denonmaryland/softly), where this plugin's source is kept under `Linux/plugin` and published here on every release.

<br>

<div align="center">
<sub>MIT licensed · built on <a href="https://omarchy.org">Omarchy</a>, <a href="https://voxtype.io">Voxtype</a> and whisper.cpp · made by <a href="https://github.com/denonmaryland">denonmaryland</a></sub>
</div>
