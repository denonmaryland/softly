#!/usr/bin/env bash
# Installs the Omarchy plugin from this repo onto this machine and restarts
# the shell (QML hot-reload keeps stale components). The plugin's own
# "Set up" (panel, or helpers/control.py setup <key>) handles Voxtype, the
# paste helper and the Hyprland module.
set -euo pipefail
cd "$(dirname "$0")"
rsync -a --delete --exclude '__pycache__' plugin/ "$HOME/.config/omarchy/plugins/io.github.denonmaryland.softly/"
omarchy restart shell
echo "Softly plugin $(python3 -c 'import json;print(json.load(open("plugin/manifest.json"))["version"])') deployed"
