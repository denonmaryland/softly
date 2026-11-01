#!/usr/bin/env bash
# Installs the Omarchy plugin and the paste helper from this repo onto this
# machine, then restarts the shell (QML hot-reload keeps stale components).
set -euo pipefail
cd "$(dirname "$0")"
rsync -a --delete --exclude '__pycache__' denon.softly/ "$HOME/.config/omarchy/plugins/denon.softly/"
install -m 755 bin/voxtype-app-paste "$HOME/.local/bin/voxtype-app-paste"
omarchy restart shell
echo "Softly plugin $(python3 -c 'import json;print(json.load(open("denon.softly/manifest.json"))["version"])') deployed"
