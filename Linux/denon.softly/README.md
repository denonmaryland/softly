# Softly (Omarchy plugin)

Two parts, one plugin:

- `Service.qml` — the pill. Hold F9 (or double-tap for hands-free), release
  to transcribe and paste through Voxtype. Esc or the × cancels. Theme colours,
  backlit groove, open/close sound cues in `sounds/`. `Controller.js` is the
  gesture state machine (shared logic with the Mac app).
- `Panel.qml` — the bar popover: Play sounds, the vocabulary list, service
  status and Preview pill. The Linux counterpart of the Mac app's window.

Settings:

- Sounds: `~/.config/omarchy/softly.json` (`{"sounds": true}`), read live by
  the pill.
- Vocabulary: Voxtype's `whisper.initial_prompt` ("A, B, C."), written through
  `helpers/control.py`, which restarts the `voxtype` user service. Same format
  as the Mac app's list, so the two can be copied across by hand.

`helpers/control.py state | set sounds true|false | add <word> | remove <word> | restart | remember <file> | clear-recent`
prints a JSON snapshot after each command.

Recent dictations: the paste helper keeps the last five transcripts in
`$XDG_RUNTIME_DIR/softly/recent.json` (tmpfs, gone at logout, never on disk)
so the popover can show them with a Copy button. "Clear" forgets them.

The widget is placed on the bar by `bar.layout` in `~/.config/omarchy/shell.json`
(`{"id": "denon.softly"}`); `omarchy bar put` reports success without
writing it when the plugin is already enrolled as a service.
