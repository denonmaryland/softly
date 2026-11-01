# Softly for Windows

The same app as the Mac and Linux versions: hold **Right Alt** to dictate,
release to transcribe and paste; double-tap for hands-free; Esc or the ×
cancels. Local Whisper (whisper.cpp through Whisper.net) on the GPU via
Vulkan when the driver allows it, otherwise CPU. Nothing leaves the PC.

```
Softly.Core/        Gestures, easing, glyph morph, waveform, transcript cleanup (port of DictationCore)
Softly.Core.Tests/  xunit port of the Mac core tests
Softly/             WPF app: tray icon, keyboard hook, WASAPI capture, pill overlay, window
```

## Build and run

Requirements: Windows 10 1809 or later, .NET 8 SDK. The build is
self-contained, so the machine running the app needs no runtime.

```powershell
dotnet test Softly.Core.Tests
dotnet build Softly -c Release
.\Softly\bin\Release\net8.0-windows10.0.19041.0\win-x64\Softly.exe
```

Model: `ggml-small.en-q5_1.bin` in `%LOCALAPPDATA%\Softly\Models\`
(download from Hugging Face `ggerganov/whisper.cpp`; the tray menu's
"Show Model Folder" opens the folder when it is missing).

Settings persist in `%APPDATA%\Softly\settings.json`; a log lands in
`%LOCALAPPDATA%\Softly\softly.log` only if something goes wrong.

## Differences from the other platforms

| | Windows | Mac | Linux |
|---|---|---|---|
| Hotkey | Right Alt (swallowed, so apps never see a bare Alt) | Right Option | F9 |
| Paste | Clipboard + synthetic Ctrl+V | Clipboard + ⌘V | Voxtype output helper |
| Media pausing | System media sessions (any player) | Music, Spotify via AppleScript | Voxtype `pause_media` |
| Accent colour | Windows accent | macOS accent | Omarchy theme |
| Permissions | None to grant; microphone privacy must allow desktop apps | Mic, Input Monitoring, Accessibility | n/a |

Right Alt is AltGr on some keyboard layouts (German, Nordic, and others);
on those the hotkey will swallow AltGr characters while Softly runs. The
US layout is unaffected.

## Control pipe

`\\.\pipe\softly-control` takes one line and answers one line:
`state`, `preview`, `open`, `cancel`, `quit`, `paste <text>`,
`transcribe <wav path>`. It exists for scripts and tests.
