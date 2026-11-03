# Softly for Windows

The same app as the Mac and Linux versions: tap **Right Alt** to start dictating
and tap it again to transcribe and paste, or hold it and release; Esc or the ×
cancels. Shortcut → Change picks another key: Right Ctrl, Right Win or a
function key. Speech runs on the PC: Whisper (whisper.cpp through Whisper.net)
on the GPU via Vulkan when the driver allows it, otherwise the CPU, or NVIDIA
Parakeet through sherpa-onnx on the CPU. Nothing leaves the PC.

```
Softly.Core/        Gestures, easing, glyph morph, waveform, transcript cleanup, fix rules,
                    the "submit" word, cutting long recordings at pauses (port of DictationCore)
Softly.Core.Tests/  xunit port of the Mac core tests
Softly/             WPF app: tray icon, keyboard hook, WASAPI capture, Whisper and Parakeet,
                    pill overlay, window (Home, Speech, Words, Shortcut, Look, About)
```

## Build and run

Requirements: Windows 10 1809 or later, .NET 8 SDK. The build is
self-contained, so the machine running the app needs no runtime.

```powershell
dotnet test Softly.Core.Tests
dotnet build Softly -c Release
.\Softly\bin\Release\net8.0-windows10.0.19041.0\win-x64\Softly.exe
```

Models live in `%LOCALAPPDATA%\Softly\Models\`: Fast, Balanced (the default,
`ggml-small.en-q5_1.bin`) and Accurate as whisper.cpp files, Parakeet as four
ONNX files in its own folder. Speech downloads a model when you pick it, and
every file is checked against its SHA-256 before the engine loads it.

Settings persist in `%APPDATA%\Softly\settings.json`; a log lands in
`%LOCALAPPDATA%\Softly\softly.log` only if something goes wrong.

## Differences from the other platforms

| | Windows | Mac | Linux |
|---|---|---|---|
| Hotkey | Right Alt by default (swallowed, so apps never see a bare Alt); Right Ctrl, Right Win or F1–F24 | Right Option by default; Right Command, Right Control or a function key | F9 by default; Right Alt, Right Ctrl, Right Super, F8, F10–F12 in the popover |
| Paste | Clipboard + synthetic Ctrl+V | Clipboard + ⌘V | Voxtype output helper |
| Media pausing | System media sessions (any player) | Music, Spotify via AppleScript | Voxtype `pause_media` |
| Pill style | 11 styles in Look (Midnight uses the Windows accent) | 11 styles in Look (Midnight uses the macOS accent) | Follows the Omarchy theme |
| Parakeet | sherpa-onnx on the CPU; vocabulary through fix rules | FluidAudio on the Neural Engine; vocabulary boosted | Voxtype's ONNX build; vocabulary through fix rules |
| Permissions | None to grant; microphone privacy must allow desktop apps | Mic, Input Monitoring, Accessibility | n/a |

Right Alt is AltGr on some keyboard layouts (German, Nordic, and others);
on those the hotkey will swallow AltGr characters while Softly runs; pick
another key in Shortcut. The US layout is unaffected.

## Control pipe

`\\.\pipe\softly-control` takes one line and answers one line:
`state`, `preview`, `open`, `show <section>`, `cancel`, `toggle`, `quit`,
`paste <text>`, `transcribe <wav path>`, `transcribe-ahead <wav path>`,
`choose-model <id>`, `choose-language <code>`, `model-state`,
`download-model`, `download-state`, `check-update`, `update-state`,
`install-update`. It exists for scripts and tests.
