#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BASE="https://raw.githubusercontent.com/Admiral456/Warrior-Land-commands/main"
ARCHIVE="$TMP/WarriorLand-Commands-1.15.8.zip"
DEST="$TMP/source"
mkdir -p "$DEST"
curl -fsSL "$BASE/WarriorLand-Commands-1.15.8.zip" -o "$ARCHIVE"
unzip -q "$ARCHIVE" -d "$DEST"
SRC="$DEST/WarriorLandCommandUnlocks-1.15.8"
test -f "$SRC/build.gradle.kts"
test -f "$SRC/web/index.html"

PATCH_B64="$TMP/source.patch.b64"
for part in part01.b64 part02.b64 part03a.b64 part03b.b64 part04.b64 part05.b64 part06.b64 part07a.b64 part07b.b64; do
  curl -fsSL "$BASE/latest-source-upgrade/$part" >> "$PATCH_B64"
done
base64 -d "$PATCH_B64" | gunzip -c > "$TMP/source.patch"
cd "$SRC"
git init --quiet
git apply --whitespace=nowarn -p2 "$TMP/source.patch"
curl -fsSL "$BASE/latest-source-upgrade/gateway.patch.gz.b64" | base64 -d | gunzip -c > "$TMP/gateway.patch"
git apply --whitespace=nowarn -p2 "$TMP/gateway.patch"
mkdir -p web/assets/branding
curl -fsSL "$BASE/latest-source-upgrade/default-skin.png.b64" | base64 -d > web/assets/branding/warriorland-default-skin.png
test -s web/assets/branding/warriorland-default-skin.png
python3 -m pip install --disable-pip-version-check --quiet PyYAML Pillow
python3 scripts/generate_resource_pack_icons.py
python3 scripts/generate_command_icon_states.py
python3 scripts/export_web_catalog.py
mkdir -p "$ROOT/public"
cp -a web/. "$ROOT/public/"
