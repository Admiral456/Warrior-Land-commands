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
curl -fsSL "$BASE/latest-source-upgrade/web-audit-fixes.patch.gz.b64" | base64 -d | gunzip -c > "$TMP/web-audit-fixes.patch"
git apply --whitespace=nowarn -p2 "$TMP/web-audit-fixes.patch"
python3 - <<'PY'
from pathlib import Path
path = Path("web/app.js")
source = path.read_text(encoding="utf-8")
needle = "  $('.toolbar').hidden = profileMode;\n"
replacement = needle + "  $('.sort-box').hidden = tasksMode || profileMode;\n"
if replacement in source:
    pass
elif needle in source:
    source = source.replace(needle, replacement, 1)
    path.write_text(source, encoding="utf-8")
else:
    raise SystemExit("Could not find the view toolbar visibility control.")
PY
mkdir -p web/assets/branding
curl -fsSL "$BASE/latest-source-upgrade/default-skin.png.b64" | base64 -d > web/assets/branding/warriorland-default-skin.png
test -s web/assets/branding/warriorland-default-skin.png
python3 -m venv "$TMP/venv"
"$TMP/venv/bin/python" -m pip install --disable-pip-version-check --quiet PyYAML Pillow
"$TMP/venv/bin/python" scripts/generate_resource_pack_icons.py
"$TMP/venv/bin/python" scripts/generate_command_icon_states.py
"$TMP/venv/bin/python" scripts/export_web_catalog.py

# Publish the cinematic homepage and the player's supplied WarriorLand artwork.
mkdir -p web/assets/branding
# Hero wordmark is supplied as a binary Vercel deployment file.
curl -fsSL "$BASE/site-home/index.html" -o web/index.html
curl -fsSL "$BASE/site-home/home.css" -o web/home.css
test -s web/assets/branding/warriorland-hero-mark.webp
test -s web/index.html
test -s web/home.css

python3 - <<'PY'
from pathlib import Path
path = Path("web/app.js")
source = path.read_text(encoding="utf-8")

old_state = "category: 'all', view: 'all', filter: 'all'"
new_state = "category: 'all', view: 'home', filter: 'all'"
if new_state not in source:
    if old_state not in source:
        raise SystemExit("Could not find initial Player Hub view state.")
    source = source.replace(old_state, new_state, 1)

nav_anchor = "  $('#mobileMenu').addEventListener('click', () => $('#sidebar').classList.toggle('mobile-open'));\n"
nav_code = """  const navigate = target => {
    if (target === 'ranking') { showToast('Žebříček hráčů bude dostupný po připojení serverových dat.'); return; }
    if (target === 'help') { showToast('Nápověda: účet propojíš ve hře příkazem /web register.'); return; }
    if (!['home', 'all', 'mine', 'tasks', 'profile'].includes(target)) return;
    if (state.view === 'profile' && target !== 'profile') disposeSkinViewer();
    state.view = target;
    state.profileRendered = false;
    state.page = 0;
    state.filter = 'all';
    updateFilterButtons();
    render();
    if (target === 'home') window.scrollTo({ top: 0, behavior: 'smooth' });
    else document.querySelector('.workspace')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  document.querySelectorAll('[data-nav]').forEach(button => button.addEventListener('click', () => navigate(button.dataset.nav)));
  document.querySelectorAll('[data-home-action]').forEach(button => button.addEventListener('click', () => navigate(button.dataset.homeAction)));
  document.querySelectorAll('[data-home-category]').forEach(button => button.addEventListener('click', () => {
    state.category = button.dataset.homeCategory;
    renderCategories();
    navigate('all');
  }));
"""
if nav_code not in source:
    if nav_anchor not in source:
        raise SystemExit("Could not find mobile menu control to attach homepage navigation.")
    source = source.replace(nav_anchor, nav_anchor + nav_code, 1)

render_anchor = "function render() {\n  const items = getFilteredItems();\n"
render_code = """function render() {
  const homeMode = state.view === 'home';
  $('#homeView').hidden = !homeMode;
  $('.workspace').hidden = homeMode;
  $('.demo-banner').hidden = homeMode;
  document.querySelectorAll('[data-nav]').forEach(button => {
    button.classList.toggle('active', button.dataset.nav === state.view);
  });
  document.querySelectorAll('[data-view]').forEach(tab => {
    const active = tab.dataset.view === state.view;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', String(active));
  });
  if (homeMode) {
    const count = state.catalog.unlocks.length;
    $('#homeCommandCount').textContent = String(count);
    $('#homeTaskCount').textContent = String(state.catalog.unlocks.reduce((total, item) => total + (item.tasks?.length || 0), 0));
    $('#homeIconCount').textContent = String(count * 6);
    return;
  }
  const items = getFilteredItems();
"""
if render_code not in source:
    if render_anchor not in source:
        raise SystemExit("Could not find render() start for home view switch.")
    source = source.replace(render_anchor, render_code, 1)

path.write_text(source, encoding="utf-8")
PY

mkdir -p "$ROOT/public"
cp -a web/. "$ROOT/public/"
