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

codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/whisper.framework"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
if [[ $IDENTITY == "-" ]]; then
  cat <<'NOTE'
Ad-hoc signed: macOS may silently stop honouring the Input Monitoring and
Accessibility grants after a rebuild (they still look enabled). If the hotkey
stops working, reset them and grant again when prompted:
  tccutil reset ListenEvent com.denon.Softly
  tccutil reset Accessibility com.denon.Softly
Creating the "Softly Local" certificate (see README) avoids this.
NOTE
fi

if [[ ${1:-} == --install ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x Softly 2>/dev/null || true
  rm -rf "$HOME/Applications/Softly.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Softly.app"
  echo "Installed to ~/Applications and launched."
fi
