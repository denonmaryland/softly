# Softly for macOS

A menu-bar dictation app for the Mac, ported from the Linux Omarchy
"Softly" setup. It uses the same local Whisper model and settings and
draws the same backlit-groove pill with the same motion. Nothing leaves the Mac.

Status: **running on the Mac.** Dictation, paste and the pill work. The
window (Home, Vocabulary, Preferences) following the chosen "Quiet Native"
direction is written but has not been compiled yet; see `docs/ui-spec.md`.

## How it works

- Hold **Right Option (⌥)** to dictate; release to transcribe and paste.
- **Double-tap** Right Option for hands-free mode; press it again to finish.
- **Esc**, or clicking the **×** that appears when you hover the timer,
  cancels and discards. Esc is only intercepted while the pill is showing.
- Typing another key while holding Right Option (an Option shortcut or an
  accented character) discards the recording instead of dictating.
- The transcript is pasted with ⌘V into the app you were in. It stays on the
  clipboard afterwards, as on Linux, so you can paste it again.
- Recording is capped at 15 minutes. Audio is held in memory only.
- Music and Spotify pause while you record and resume afterwards, as Voxtype
  does on Linux. macOS asks once per app for Automation access. Off switch in
  Preferences.
- **Open Softly…** in the menu-bar menu (or ⌘, while the window is
  up) opens the window: Home shows status and a practice box, Vocabulary
  edits the names Whisper is hinted with, Preferences has sounds, microphone,
  model status and the three permissions. The window also opens on its own
  when a permission or the model is missing.

| Part | Linux original | Mac version |
|---|---|---|
| Speech model | Voxtype + whisper.cpp (Vulkan), `ggml-small.en-q5_1.bin` | whisper.cpp xcframework (Metal), same model file |
| Settings | English, flash attention, 4 threads, vocabulary prompt | Same, in `Sources/Softly/Settings.swift` |
| Gestures | `Controller.js` | `GestureController.swift` (same rules, same tests) |
| Pill | Quickshell QML | SwiftUI Canvas in a non-activating `NSPanel` |
| Paste | `voxtype-app-paste` + Hyprland | `NSPasteboard` + synthetic ⌘V |
| Accent colour | Omarchy theme | macOS accent colour (System Settings → Appearance) |
| Settings | Bar popover (sounds, vocabulary, status) | Window (Home, Vocabulary, Preferences) |
| Media pausing | Voxtype `pause_media` (MPRIS) | `MediaPauser.swift` (Music, Spotify via AppleScript) |

## Layout

```
Package.swift                SwiftPM package (macOS 14+)
Sources/DictationCore/       Gestures, easing/tweens, glyph morph, waveform, transcript cleanup
Sources/Softly/      App: menu bar, hotkey tap, mic, Whisper, paste, pill, window
Tests/DictationCoreTests/    Unit tests for the core (also run on Linux)
Windows/                     Softly for Windows (.NET 8, WPF, Whisper.net); own README
Resources/                   Info.plist, open/close sound cues
scripts/build-app.sh         Builds and signs "Softly.app"
scripts/fetch-model.sh       Downloads and verifies the Whisper model
docs/ui-spec.md              Window and pill spec from the Paper design (direction 01)
Linux/plugin/                The Omarchy plugin, published to github.com/denonmaryland/omarchy-softly
VERSION, scripts/release.sh  One version for all platforms; release.sh tags and pushes
.github/workflows/release.yml Builds and publishes all three on a v* tag
.github/workflows/build.yml  Optional macOS CI build (only if pushed to GitHub)
```

## Build and install (on the Mac)

Requirements: macOS 14 or later, Xcode 16 or later (open it once to accept the
licence). Apple Silicon recommended.

```bash
git clone <this repo> ~/Projects/quiet-dictation-mac   # or copy the folder over
cd ~/Projects/quiet-dictation-mac
scripts/fetch-model.sh          # or copy the .bin from the Linux laptop (see below)
swift test                      # core logic tests
scripts/build-app.sh --install  # builds, installs to ~/Applications, launches
```

Copying the model from Linux instead of downloading it:

```bash
scp denon@<linux-host>:~/.local/share/voxtype/models/ggml-small.en-q5_1.bin \
  "$HOME/Library/Application Support/Softly/Models/"
```

On first launch macOS asks for **Microphone**, **Input Monitoring** and
**Accessibility** access. Input Monitoring is for the Right Option hotkey;
Accessibility is for pasting with ⌘V and intercepting Esc. The menu-bar icon
shows a warning badge until everything is ready, and its menu links to each
settings pane.

### Keeping permissions across rebuilds

Ad-hoc signed builds can make macOS forget the Input Monitoring and
Accessibility grants after each rebuild. To avoid that, create a local signing
certificate once:

1. Open Keychain Access → Certificate Assistant → Create a Certificate…
2. Name it **Softly Local**, Identity Type *Self Signed Root*,
   Certificate Type *Code Signing*.

`build-app.sh` uses it automatically when present.

## Updates

Every copy of Softly checks GitHub Releases quietly a few hours apart and
offers the new build in Preferences (Mac and Windows) or the bar popover
(Linux). To ship one: `scripts/release.sh X.Y.Z` bumps the version on all
three platforms, tags, and pushes; GitHub Actions builds the Mac app, the
Windows app and the Omarchy plugin and attaches them to the release.

## Customizing

- Vocabulary: the window's Vocabulary view (stored in UserDefaults; first-run
  defaults in `Settings.defaultVocabulary`). Language, threads: `Settings.swift`.
- Hotkey: `HotkeyMonitor.swift` (`triggerKeyCode`, `rightOptionMask`).
- Pill colours: `Palette.swift`. Motion timings: `PillModel.swift`.

## Known limitations

- Paste sends the physical V key with ⌘. Non-QWERTY layouts (for example
  Dvorak) may need a layout-aware key code.
- Bluetooth headsets switch to a lower-quality microphone profile while
  recording, which can reduce accuracy. The built-in microphone avoids this.
- The Preferences window shows the shortcut and microphone but does not let
  you change them yet; both follow the code and the system input device.
- Recordings whose loudest moment stays under `Settings.silenceRMS` (0.005)
  are skipped, because Whisper invents text for silence. If soft speech is
  being dropped, lower it.
- If the microphone changes mid-recording (for example AirPods connect), the
  recording stops and what was captured is transcribed.
- The pill appears on the screen under the pointer, above the Dock.
