# Changelog

## 0.2.10

- Dictation pastes into Herdr. Herdr's terminal panes ignored the Ctrl+V
  Softly sent (Codex read it as "paste an image"); Herdr now gets its own
  Ctrl+Shift+V. After updating, press Set up Softly in the popover once so
  the new paste helper is installed.

## 0.2.9

- No changes to the plugin; this version keeps it in step with the Mac and
  Windows apps.

## 0.2.8

- Pick your dictation key in the popover: Dictation key → Change offers F9,
  Right Alt, Right Ctrl, Right Super, F8, F10, F11 and F12. Switching
  rewrites Softly's Hyprland binding straight away. The Mac and Windows
  apps get a Change button that records the next key you press.

## 0.2.7

- A lone modifier works as the dictation key: set the hotkey to Alt_R
  (Right Alt), Super_R, Control_R or Shift_R and tap or hold it like F9.
  The popover names it as "Right Alt" and so on.

## 0.2.6

- New "Tap to start and stop" switch in the popover, on by default. Turn
  it off for hold-only: hold the key while you talk and let go to finish.
  The Mac and Windows apps get the same switch in Preferences.

## 0.2.5

- The pill still follows your Omarchy theme. For anyone who wants a fixed
  look, "Pill style" in the popover has a Change link with eleven styles
  (seven dark, three light, and Midnight); pick Omarchy to follow the
  theme again. The Mac and Windows apps get the same styles in Preferences.

## 0.2.4

- One tap starts hands-free dictation and the next tap finishes it; no
  more double-tap. Holding the key for half a second or longer still
  works as push-to-talk and finishes on release.

## 0.2.3

- No plugin changes; the version follows the Windows app, which now
  responds to the key immediately on a busy PC.

## 0.2.2

- No plugin changes; the version follows the Windows app, which now adds
  itself to the Start menu.

## 0.2.1

- No plugin changes; the version follows the Mac and Windows apps, which
  now keep their macOS permissions across updates.

## 0.2.0

- Popover wording: the vocabulary and status lines name Softly rather than
  the model. No behaviour change.

## 0.1.0

- First public release: the pill, the bar popover (sounds, recent
  transcripts, vocabulary, status, preview), consent-based Set up and Remove,
  a configurable dictation key, and update checks through
  `omarchy plugin update`.
