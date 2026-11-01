# Softly — Mac window spec (direction 01 "Quiet Native")

Decision: DeNon chose direction **01 Quiet Native** on 1 November 2026 from the
Paper study "Softly — Three Mac Directions · Nov 2026"
(https://app.paper.design/file/01M6BGN8JVYN39Y62VKMNW27AZ, page "01 Quiet Native").
This file turns those three artboards into values a build can follow.
Values are the light-mode reference; see "Semantic mapping" for what to use
in code so dark mode comes for free.

## Build status (1 Nov 2026)

Steps 1–3 below are built, compiled on the Mac and installed (1 Nov 2026).
Step 4 is closed: **the pill stays as it is.** DeNon chose the dark backlit
groove, the look the Linux plugin has today, for both platforms. The light
"01" pill in the Paper file is not being built; the section below is kept as
a record of what was drawn.

## What gets built, in order

1. **Preferences** window. Biggest gap: the app has no settings UI at all today
   (options live in `Settings.swift` and the menu-bar menu).
2. **Home** view in the same window: status, shortcut explainer, practice box.
3. **Vocabulary** view. 01 has no artboard for it; use the row structure from
   the Warm Flow "Vocabulary & Setup" artboard (page "02 Warm Flow") restyled
   with the values below. Requires `Settings.initialPrompt` to become a
   user-editable list stored in UserDefaults.
4. ~~Pill restyle to the 01 light pill.~~ Decided against; see Build status.

Design-only labels ("WINDOW CONCEPT", "EDITABLE SETTINGS · CONCEPT",
"PRACTICE AREA · CONCEPT", the "proposals" footnote) are not built.

## Window shell

- Reference size 1040 × 720, corner radius 14 (system window chrome supplies this).
- Standard traffic lights; the window is a normal titled window with a hidden
  title and full-size content view so the sidebar runs to the top.
- The app is `.accessory` (no Dock icon). Opening the window must call
  `NSApp.activate(ignoringOtherApps: true)` and the window must be ordinary
  (not the non-activating pill panel), or it will never take focus.
- Open from a new menu item "Open Softly…" (⌘,) and on first launch
  when a permission or the model is missing. Closing the window never quits.

### Sidebar (left, 220 wide)

| Element | Value |
|---|---|
| Background | `#F0F2F4`, 1 px right border `#DFE3E7` |
| Padding | 26 top/bottom, 18 sides; sections stacked with 28 gap |
| Brand row | mic glyph 24 pt (SF Symbol `mic`, accent colour) + "Softly" 16 pt bold, 10 gap, 12/10 padding |
| Nav item | 15 pt, 11 vertical / 14 horizontal padding, radius 7, items 7 apart |
| Nav selected | background `#DCEAFF`, text `#0064D5` semibold |
| Nav items | Home, Vocabulary, Preferences |
| Footer (pinned 28 from bottom, 28 from left) | "ON THIS MAC" 11 pt semibold `#65707C` · "Whisper · English" 13 pt `#46525E` · "Audio held in memory only" 12 pt `#65707C`, 7 gap |

### Content header (right, full width, 66 tall)

- Title 16 pt semibold `#20252B`, padding 22 vertical / 34 horizontal.
- 1 px bottom border `#EDF0F2`.
- Nothing on the right side in the build.

### Content column

- Starts 48 pt right of the sidebar (x = 268 in the reference), width 724.
- First element sits 106–108 pt from the top of the window.

## Home

| Block | Value |
|---|---|
| Status line | 7 pt dot + "Ready to dictate", 13 pt semibold, both `#27834A`, 7 gap. Other states reuse the menu-bar status strings (model loading, missing model, waiting for permissions) in `#65707C` with a grey dot. |
| Headline | "Your words. Right where you need them." 32 pt bold, line height 43, `#20252B`; 14 gap below status |
| Subhead | "Speak into the app you're using. Softly takes it from here." 15 pt `#65707C` |
| Shortcut card | 724 wide, background `#F6F8FA`, 1 px border `#E2E7EC`, radius 12, padding 24, horizontal with 26 gap; starts 265 from top |
| Keycap | "Right ⌥" 15 pt semibold `#39424C`; background `#F4F5F6`, 1 px border `#D5D9DE`, radius 7, 8/14 padding, 2 pt bottom shadow `#D5D9DE` (no blur) |
| Card text | "Hold to speak. Release to paste." 18 pt semibold `#20252B`; "Double-tap for hands-free. Press again to finish." 14 pt `#65707C`; 6 gap |
| Section title | "Try it here" 20 pt semibold; starts 407 from top |
| Practice box | 724 × 154, 1 px border `#C9D0D8`, radius 9, padding 20. Placeholder "Click here, then hold Right Option and say something." 16 pt `#7B8490`. Bottom row: "A temporary place to get comfortable." 13 pt `#65707C` and a "Clear" button (13 pt `#65707C`, background `#F8F9FA`, border `#DCE1E6`, radius 6, 6/12 padding). |
| Footer | "Local Whisper. No audio saved. No transcript history." 13 pt medium `#46525E`; "Esc cancels · Your transcript stays on the clipboard after pasting." 13 pt `#65707C`; 6 gap; starts 633 from top |

Practice box behaviour: a plain editable text view. Dictating while it has
focus pastes into it like any other app; nothing is persisted. Clear empties it.

## Preferences

| Block | Value |
|---|---|
| Headline | "Make yourself at home." 30 pt bold, line height 41, `#20252B`; starts 108 from top |
| Subhead | "A few quiet controls. Everything stays on this Mac." 15 pt `#65707C`, 10 gap |
| Row | 18 pt vertical padding, 1 px bottom border `#E5E8EB`, 20 gap between text and control; rows start 205 from top and are 86 apart |
| Row title | 15 pt medium `#20252B` |
| Row subtitle | 13 pt `#65707C`, 4 gap below title |
| Trailing slot | fixed 180 wide, content right-aligned (keeps controls in one lane) |

Rows:

1. **Dictation shortcut** — "Hold to record · double-tap for hands-free" — keycap "Right ⌥" (same style as Home). Display only in v1; the hotkey stays fixed in `HotkeyMonitor.swift`.
2. **Play sounds** — "A subtle cue when recording starts and ends" — system toggle, bound to `Settings.soundsEnabled`. Replaces the menu-bar checkbox (keep the menu item too; both read the same default).
3. **Microphone** — "Use the microphone selected in macOS" — popup, 14 pt medium `#46525E`, single item "System default" in v1. The recorder already follows the system input device.
4. **Speech model** — "Whisper small.en · Q5_1 · English" — status text 14 pt medium: `#27834A` "Loaded on this Mac" when `modelStatus == .ready`; otherwise `#65707C` "Loading…", or a "Show Model Folder" link when missing.

Permissions block (starts 578 from top, 12 gap between lines):

- "PERMISSIONS" 11 pt semibold `#65707C`.
- Three items 24 apart, 13 pt: "✓ Microphone", "✓ Input Monitoring", "✓ Accessibility" in `#27834A` when granted. When not granted: "○ Name" in `#65707C`, clickable, opens the matching System Settings pane via `Permissions.openSettings`.

## Pill (01 light pill) — not adopted

Static reference from the "Recording → Processing → Success" artboard. The
motion in `PillModel.swift` stays; only the surface and colours change.

| Element | Value |
|---|---|
| Capsule | 302 × 54, white `#FFFFFF`, 1 px border `#D7DDE4`, radius 28, horizontal padding 18 |
| Shadow | 0 7 18 `#20252B` at 8 % (recording and processing); none on success |
| Left slot | fixed 112 wide, content centred |
| Waveform | 17 bars, 3 wide, 6 pitch, radius 1.5, height 6–28, fill `#007AFF` |
| Timer | "0:08" 13 pt medium `#20252B` |
| Cancel | "×" 17 pt `#20252B`, far right |
| Processing | three 5 pt dots `#007AFF` at 100 / 75 / 50 % opacity, 5 gap; label "Transcribing" |
| Success | 22 pt check, `#007AFF` stroke 2, round caps; label "Pasted" |

The current pill is 153 × 32 with a backlit groove. Moving to this one means
new geometry in `PillGeometry`, a light `Palette`, and dropping the groove and
shadow layers in `PillView.swift`. Decide before starting whether the system
accent colour should replace `#007AFF` (it should: the design is system blue).

## Semantic mapping (use these in code)

| Reference hex | Use |
|---|---|
| `#007AFF`, `#0064D5`, `#DCEAFF` | `Color.accentColor` / `NSColor.controlAccentColor`; selection background = accent at 15 % |
| `#20252B`, `#000000` | `Color.primary` / `labelColor` |
| `#46525E`, `#39424C` | `secondaryLabelColor` |
| `#65707C`, `#7B8490` | `tertiaryLabelColor` for captions, `secondaryLabelColor` for body |
| `#F0F2F4` sidebar | `NSVisualEffectView` sidebar material, or `windowBackgroundColor` darkened |
| `#FFFFFF` content | `windowBackgroundColor` |
| `#E5E8EB`, `#EDF0F2`, `#DFE3E7`, `#D7DDE4` | `separatorColor` |
| `#F6F8FA`, `#F4F5F6`, `#F8F9FA` | `controlBackgroundColor` or `quaternaryLabelColor` at low opacity |
| `#27834A` | `systemGreen` |

Type is the system font throughout: SF Pro via `.system(size:weight:)`. Line
heights above are what Paper rendered; let SwiftUI's defaults stand unless a
block visibly drifts from the artboard.

## Engineering notes

- Build target stays SwiftPM, macOS 14+. Use `NavigationSplitView` with a
  custom sidebar list (plain `List` with `.listStyle(.sidebar)` gets the
  material and selection for free; override selection colour only if it
  drifts from `#DCEAFF`).
- Window state lives in a small `AppWindowController` owned by `AppDelegate`,
  so the engine, hotkeys and permissions it already holds can be observed.
- `Settings` gains: `vocabulary: [String]` (replaces the constant
  `initialPrompt`; join with ", " when building the Whisper prompt) and
  nothing else in v1.
- Status strings on Home and in the menu come from one place
  (`AppDelegate.statusLine` today; lift it onto the engine).
- No Linux build for the Mac target; the DictationCore tests still run here.
  First compile happens on the Mac via `scripts/build-app.sh --install`.
