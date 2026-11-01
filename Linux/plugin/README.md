# Softly

Hold a key, speak, release. Local Whisper dictation for Omarchy, through
the Voxtype daemon Omarchy already ships, with a quiet backlit pill instead
of Voxtype's overlay and a bar popover for the few settings that matter.
Nothing leaves the machine.

![Softly's popover on the bar](preview.png)

## What it does

- **Hold F9** (or the key you choose) to record; release to transcribe and
  paste into the app you were in. **Double-tap** for hands-free; press again
  to finish. **Esc** or the × on the pill cancels.
- **The pill**: a small theme-coloured capsule at the bottom of the screen
  with a live waveform, a timer, and a backlit groove that dims while Whisper
  works. It follows the Omarchy theme.
- **App-aware paste**: Ctrl+V for normal apps, Shift+Insert for windows tagged
  terminal, sent through Hyprland. The transcript stays on the clipboard.
- **The popover** (click the microphone in the bar): sounds on or off,
  the last few transcripts with copy buttons, your vocabulary (names Whisper
  gets wrong, saved to Voxtype's prompt), status, and a preview of the pill.
- **Keyboard**: Up/Down move between rows, Enter activates.

## Install

```bash
omarchy plugin add https://github.com/denonmaryland/omarchy-softly --enable
```

Then click the microphone icon in the bar and press **Set up Softly**. With
your consent it writes three things, each backed up first
(`name.bak.<time>-softly`):

1. `~/.local/bin/softly-paste`, the paste helper.
2. Voxtype's output settings in `~/.config/voxtype/config.toml`: clipboard
   output through that helper, Voxtype's own overlay and hotkey off.
3. `~/.config/hypr/softly.lua` for your dictation key, loaded by one marked
   line at the end of `~/.config/hypr/hyprland.lua`. With F9 it replaces
   Omarchy's stock Voxtype binding; other keys leave F9 alone.

Change the key under the widget's settings (**Dictation key**), then press
**Apply** in the popover.

## Remove

In the popover, **Remove Softly's setup from this machine** undoes the three
writes above (Voxtype keys go back to their defaults, the Hyprland line and
module are removed, the helper is deleted). Then:

```bash
omarchy plugin remove io.github.denonmaryland.softly
```

Your vocabulary stays in Voxtype's config; sounds setting lives in
`~/.config/omarchy/softly.json` and can be deleted.

## Dependencies

All part of a stock Omarchy install: **Voxtype** (the dictation daemon and
its Whisper model; the plugin never installs it, only checks that it is
there), `wl-clipboard`, `jq`, `hyprctl`, `python3`. The only service it
touches is your own user-level `voxtype` service, restarted after a
vocabulary change or Set up. No sudo or pkexec is required. The plugin talks
to the network only when you press **Check for updates**, which reads the
latest release tag on GitHub; updates install through `omarchy plugin update`.

## Files it touches

| Path | Why |
|---|---|
| `~/.config/omarchy/softly.json` | the sounds switch |
| `$XDG_RUNTIME_DIR/softly/` | recent transcripts (tmpfs, gone at logout) and paste state |
| `~/.config/voxtype/config.toml` | output settings, on Set up (backed up) |
| `~/.config/hypr/softly.lua`, one line in `hyprland.lua` | the key binding, on Set up (backed up) |
| `~/.local/bin/softly-paste` | the paste helper, on Set up |

## Same app elsewhere

Softly also exists for macOS and Windows with the same pill and the same
gesture rules; see the [Softly repo](https://github.com/denonmaryland/softly).
This plugin's source lives there under `Linux/plugin` and is published here.

## License

MIT, see [LICENSE](LICENSE).
