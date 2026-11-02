#!/usr/bin/env bash
# scripts/release.sh 0.2.0
# Bumps every platform's version, commits, tags vX.Y.Z and pushes. GitHub
# Actions (.github/workflows/release.yml) then builds the Mac app, the
# Windows app and the Omarchy plugin and attaches them to the release, which
# every installed copy of Softly offers through "Check for updates".
set -euo pipefail
cd "$(dirname "$0")/.."
v=${1:?usage: scripts/release.sh X.Y.Z}
[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z" >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || { echo "commit or stash changes first" >&2; exit 2; }

echo "$v" > VERSION
# Mac: CFBundleShortVersionString and CFBundleVersion
python3 - "$v" <<'PY'
import re, sys
v = sys.argv[1]
p = "Resources/Info.plist"; s = open(p).read()
s = re.sub(r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*", r"\g<1>" + v, s)
s = re.sub(r"(<key>CFBundleVersion</key>\s*<string>)[^<]*", r"\g<1>" + v, s)
open(p, "w").write(s)
p = "Windows/Softly/Softly.csproj"; s = open(p).read()
s = re.sub(r"<Version>[^<]*</Version>", f"<Version>{v}</Version>", s)
open(p, "w").write(s)
import json
p = "Linux/plugin/manifest.json"; m = json.load(open(p)); m["version"] = v
json.dump(m, open(p, "w"), indent=2); open(p, "a").write("\n")
PY
git add -A
git commit -m "Softly $v"
git tag -a "v$v" -m "Softly $v"
git push origin HEAD "v$v"
# The Omarchy plugin is listed from its own repo with the plugin at the root.
split=$(git subtree split --prefix=Linux/plugin)
git push --force https://github.com/denonmaryland/omarchy-softly.git "$split:main"
git tag -f "plugin-v$v" "$split" && git push --force https://github.com/denonmaryland/omarchy-softly.git "plugin-v$v:refs/tags/v$v"
gh release create "v$v" --repo denonmaryland/omarchy-softly --title "Softly $v" --notes "See CHANGELOG.md in the plugin."
echo "Tagged v$v (apps) and pushed the plugin to omarchy-softly. Watch the release build: gh run watch"
