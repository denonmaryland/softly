<div align="center">

<img src="docs/wordmark.svg" alt="Softly" width="560">

<p><strong>Tap a key, speak, tap again. The words land where your cursor is.</strong><br>
Free, open-source dictation with the same quiet backlit pill on macOS, Windows and Omarchy Linux. Speech is recognised on your own machine; nothing leaves it.</p>

<p>
<a href="https://github.com/denonmaryland/softly/releases"><img alt="Release" src="https://img.shields.io/github/v/release/denonmaryland/softly?style=flat-square&label=release&color=4C8DFF"></a>
<img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-1E2330?style=flat-square">
<img alt="Windows" src="https://img.shields.io/badge/Windows-10%2B-1E2330?style=flat-square">
<a href="https://github.com/denonmaryland/omarchy-softly"><img alt="Omarchy plugin" src="https://img.shields.io/badge/omarchy-plugin-4C8DFF?style=flat-square"></a>
<a href="https://github.com/denonmaryland/softly/blob/main/VERSION"><img alt="Speech on device" src="https://img.shields.io/badge/speech-on%20device-1E2330?style=flat-square"></a>
</p>

<img src="Linux/plugin/docs/demo-dictation.gif" alt="Hold the key and speak: the pill appears, the words land in Obsidian; a tap dictates hands-free; the popover shows what was just said" width="880">

</div>

<br>

<table align="center">
<tr>
<td align="center" width="33%"><h3>Tap</h3>Right Option on the Mac, Right Alt on Windows, F9 on Omarchy, or any key you pick in settings. The pill rises with a live waveform and a timer.</td>
<td align="center" width="33%"><h3>Speak</h3>Tap once and Softly keeps listening hands-free until you tap again, or hold the key to talk. Esc or the × cancels.</td>
<td align="center" width="33%"><h3>Release</h3>The speech model runs on your machine, the groove dims while it works, and the text is pasted into the app you were in. It stays on the clipboard too.</td>
</tr>
</table>

<br>

## What it does

- **Four speech models, all on your machine.** Fast, Balanced, Accurate (Whisper) and Parakeet (NVIDIA). Pick one in Speech; the others download when you choose them.
- **Fixes for what it mishears.** "When Softly hears *cloud code*, type *Claude Code*." Rules match whole words and ignore case; an empty right side drops a word such as "um".
- **Vocabulary.** Names and terms the model should expect: hinted to Whisper, and listened for by Parakeet on the Mac.
- **Transcribes while you talk.** Long dictations are cut at natural pauses and transcribed in the background, so stopping only leaves the last few seconds. On a 50-second prompt the wait after stopping fell from 4.6 s to 2.0 s on Accurate.
- **Say "submit" to send** (off by default). End with "submit" and Softly presses Enter after pasting, so a prompt goes to an agent without touching the keyboard.
- **17 language choices**: English, detect automatically, or one of 15 others.
- **Recent dictations**, kept in memory only, to copy or paste again.
- **Your microphone**, picked in Shortcut on the Mac and Windows.
- **Music pauses** while you talk and picks up afterwards.
- **Eleven pill styles**, or the Omarchy theme on Linux.

### The speech models

| | Fast | Balanced | Accurate | Parakeet |
|---|---|---|---|---|
| Engine | Whisper base | Whisper small | Whisper large-v3-turbo | Parakeet TDT 0.6B v3 |
| Download | 60 MB | 190 MB (default) | 574 MB | 480 MB (Mac), 640 MB (Windows, Linux) |
| Best for | Short, plain sentences | Everyday speech | Names, code, jargon | Speed, especially on Apple silicon |
| Vocabulary | Hinted | Hinted | Hinted | Listened for on the Mac; fixes only on Windows and Linux |
| Runs on | GPU (Metal, Vulkan) or CPU | GPU or CPU | Best with a GPU | Neural Engine (Mac), CPU (Windows, Linux) |

For any language other than English, Fast and Balanced switch to their multilingual files; Accurate is multilingual already, and Parakeet detects 25 European languages on its own.

<br>

## One pill, three desks

<table>
<tr>
<th width="33%">macOS</th>
<th width="33%">Windows</th>
<th width="33%">Omarchy Linux</th>
</tr>
<tr>
<td valign="top">Menu-bar app in Swift. whisper.cpp with Metal, Parakeet on the Neural Engine through FluidAudio, a SwiftUI pill in a non-activating panel, paste through ⌘V. A window with Home, Speech, Words, Shortcut, Look and About. <a href="#the-mac-app">Below.</a></td>
<td valign="top">Tray app in .NET 8 and WPF. Whisper.net on Vulkan when the GPU allows it, Parakeet through sherpa-onnx, a low-level hook on Right Alt, WASAPI capture, the same window. <a href="Windows/README.md">Windows/README.md</a></td>
<td valign="top">An Omarchy plugin on Voxtype: the pill follows your theme, and a bar popover holds status, the model, the switches, recent dictations, and pages for words and fixes and for key, language and pill. <a href="https://github.com/denonmaryland/omarchy-softly">omarchy-softly</a></td>
</tr>
</table>

<div align="center">
<img src="Linux/plugin/docs/pill-themes.gif" alt="The pill follows the theme on Omarchy" width="760">
</div>

The shared logic is written once per language and tested the same way on each platform: gestures, the pill's motion and waveform, transcript cleanup, fix rules, the "submit" word and cutting long recordings at pauses (`Sources/DictationCore`, `Windows/Softly.Core`, `Linux/plugin`).

## Updates

Every copy checks GitHub Releases quietly a few hours apart and offers the new build in About (Mac and Windows) or the bar popover (Linux). To ship one: `scripts/release.sh X.Y.Z` bumps the version on all three platforms, tags, and pushes; GitHub Actions builds the Mac app, the Windows app and the Omarchy plugin, attaches them to the release, and publishes the plugin to its own repo.

<br>

# The Windows app

Windows 10 or 11, 64-bit. A GPU with Vulkan makes the Whisper models fast; without one they run on the CPU.

1. Download `Softly-windows.zip` from the [latest release](https://github.com/denonmaryland/softly/releases/latest) and unzip it anywhere, for example `C:\Softly`.
2. Run **Softly.exe**. The build is not code-signed, so SmartScreen shows "Windows protected your PC": press **More info**, then **Run anyway**. Nothing else needs installing; .NET is bundled.
3. Softly opens its window. Press **Download** next to the speech model (190 MB, once). The file is verified and kept in `%LOCALAPPDATA%\Softly\Models`.
4. Tap **Right Alt**, talk, and tap it again.

Softly lives in the tray, not the taskbar. It adds itself to the Start menu on first run, so search for **Softly** to open its window again; launching it while it is already running brings the window forward.

Details and the build steps are in [Windows/README.md](Windows/README.md).

<br>

# The Mac app

A menu-bar app for Apple silicon Macs. It draws the same backlit pill with the same motion as the other two, and nothing leaves the Mac.

### Install

Apple silicon, macOS 14 or later.

1. Download `Softly-mac.dmg` from the [latest release](https://github.com/denonmaryland/softly/releases/latest) and drag **Softly** into Applications.
2. Open it once. The build is signed but not notarized with Apple, so macOS refuses the first launch. Go to **System Settings → Privacy & Security**, scroll down, and press **Open Anyway** next to Softly. Or, in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Softly.app
   ```

3. Softly opens its window. On Home, press **Download** for the speech model (190 MB, once). Models are verified and kept in `~/Library/Application Support/Softly/Models`; Parakeet's live in FluidAudio's cache.
4. Grant **Microphone**, **Input Monitoring** and **Accessibility** when asked (About lists all three). Input Monitoring is for the dictation key; Accessibility is for pasting with ⌘V and intercepting Esc.
5. Tap **Right ⌥**, talk, and tap it again.

### How it works

- **Tap** Right Option once to dictate hands-free; tap it again to transcribe and paste. Or hold it while you talk and let go to finish. Shortcut → Change picks another key: Right Command, Right Control or a function key.
- **Esc**, or the **×** that appears when you hover the timer, cancels and discards. Esc is only intercepted while the pill is showing.
- Typing another key while holding Right Option (an Option shortcut or an accented character) discards the recording instead of dictating.
- The transcript is pasted with ⌘V into the app you were in and stays on the clipboard afterwards.
- Recording is capped at 15 minutes. Audio is held in memory only.
- Music and Spotify pause while you record and resume afterwards. macOS asks once per app for Automation access.

### The window

| Screen | What is there |
|---|---|
| Home | Status, anything still to set up, a box to try the key in, and recent dictations |
| Speech | The four models with their download state, language, and "submit" |
| Words | Vocabulary chips and the fixes list |
| Shortcut | The key, tap or hold, microphone, music pausing, sounds |
| Look | A large preview of the pill and the eleven styles |
| About | Updates, the three permissions, the model folder |

### Layout

```
Package.swift                SwiftPM package (macOS 14+): whisper.cpp xcframework, FluidAudio 0.17.7
Sources/DictationCore/       Gestures, motion, glyph, waveform, transcript cleanup, fix rules,
                             the "submit" word, cutting long recordings at pauses, languages
Sources/Softly/              App: menu bar, hotkey, mic, Whisper and Parakeet, paste, pill, window
  Gallery.swift              The window's shared pieces (sections, rows, switches, keycaps)
  SpeechModel.swift          The four models, their files and checksums
  ParakeetTranscriber.swift  Parakeet through FluidAudio, with vocabulary boosting
Tests/DictationCoreTests/    Unit tests for the core (also run on Linux)
Windows/                     Softly for Windows (.NET 8, WPF, Whisper.net, sherpa-onnx); own README
Linux/plugin/                The Omarchy plugin, published to github.com/denonmaryland/omarchy-softly
Linux/tests/                 Tests for the plugin's fix script
Resources/                   Info.plist, open/close sound cues
scripts/build-app.sh         Builds and signs "Softly.app"
scripts/fetch-model.sh       Downloads and verifies the default Whisper model
VERSION, scripts/release.sh  One version for all platforms; release.sh tags and pushes
.github/workflows/release.yml Builds and publishes all three on a v* tag
```

### Build from source

Requirements: macOS 14 or later, Xcode 16 or later (open it once to accept the licence).

```bash
git clone https://github.com/denonmaryland/softly ~/Projects/softly
cd ~/Projects/softly
swift test                      # core logic tests
scripts/build-app.sh --install  # builds, installs to ~/Applications, launches
```

Two switches help when there is no screen to look at (over SSH, in CI):

```bash
Softly --snapshot /tmp/shots    # draws every window screen, light and dark, to PNG
Softly --transcribe clip.wav    # Parakeet on a file, before and after vocabulary boosting
```

#### Keeping permissions across rebuilds

Release builds are ad-hoc signed with a designated requirement of just the bundle identifier, so Input Monitoring and Accessibility grants survive updates. Builds from before 0.2.1 were tied to one exact binary: after updating from one of those, the switches in System Settings still look on but are ignored. Remove Softly from both lists (or run `tccutil reset ListenEvent com.denon.Softly` and `tccutil reset Accessibility com.denon.Softly`), relaunch, and grant once more.

For local development you can instead sign with a certificate of your own: in Keychain Access, Certificate Assistant → Create a Certificate…, name it **Softly Local**, Identity Type *Self Signed Root*, Certificate Type *Code Signing*. `build-app.sh` uses it automatically when present.

### Known limitations

- Paste sends the physical V key with ⌘. Non-QWERTY layouts (for example Dvorak) may need a layout-aware key code.
- Bluetooth headsets switch to a lower-quality microphone profile while recording, which can reduce accuracy. The built-in microphone avoids this.
- Recordings whose loudest moment stays under `Settings.silenceRMS` (0.005) are skipped, because Whisper invents text for silence. If soft speech is being dropped, lower it.
- If the microphone changes mid-recording (for example AirPods connect), the recording stops and what was captured is transcribed.
- Parakeet's vocabulary boosting only changes a word the keyword model hears and that is spelled close to the vocabulary word; anything further off still needs a fix rule.
- The builds are not notarized (Mac) or code-signed (Windows), so each asks once before the first launch.

<br>

<div align="center">
<sub>MIT licensed · whisper.cpp by ggml · Parakeet through FluidAudio and sherpa-onnx · made by <a href="https://github.com/denonmaryland">denonmaryland</a></sub>
</div>
