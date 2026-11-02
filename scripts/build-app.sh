#!/usr/bin/env bash
# Builds "Softly.app" into ./build. Run on a Mac with Xcode installed.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy to ~/Applications and relaunch
#
# Signing: uses a "Softly Local" code-signing certificate if you have
# one (keeps macOS permissions across rebuilds), otherwise ad-hoc signs.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Softly.app"
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z $IDENTITY ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Softly Local"; then
    IDENTITY="Softly Local"
  else
    IDENTITY="-"
  fi
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/Softly" "$APP/Contents/MacOS/Softly"
FRAMEWORK="$BIN/whisper.framework"
if [[ ! -d $FRAMEWORK ]]; then
  FRAMEWORK=$(find .build/artifacts -type d -path '*macos-arm64_x86_64/whisper.framework' | head -1)
fi
[[ -d $FRAMEWORK ]] || { echo "whisper.framework not found" >&2; exit 1; }
cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"
# SwiftPM resource bundles (FluidAudio's) are found through Bundle.main.resourceURL.
for bundle in "$BIN"/*.bundle; do
  [[ -d $bundle ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/whisper.framework"
if [[ $IDENTITY == "-" ]]; then
  # An ad-hoc signature's default designated requirement is the binary's hash,
  # so macOS ties Input Monitoring and Accessibility grants to one exact build
  # and every update silently orphans them (the switches stay on, the app is
  # still refused). Requiring only the bundle identifier keeps the grants
  # across updates.
  codesign --force --sign - -r='designated => identifier "com.denon.Softly"' "$APP"
else
  codesign --force --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
codesign -d -r- "$APP" 2>&1 | tail -1

if [[ ${1:-} == --install ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x Softly 2>/dev/null || true
  rm -rf "$HOME/Applications/Softly.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Softly.app"
  echo "Installed to ~/Applications and launched."
fi
