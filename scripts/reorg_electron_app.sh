#!/usr/bin/env bash
set -euo pipefail

# Monadic Chat: Electron file reorganization script
# - Purpose: Move Electron files from the repo root into app/ and update package.json
# - Usage:
#     Dry run:    bash scripts/reorg_electron_app.sh
#     Apply:      bash scripts/reorg_electron_app.sh --apply
#     Force apply:bash scripts/reorg_electron_app.sh --apply --force
# - Scope: Electron app only (Docker/Ruby/tests are not affected)

MODE="dry-run"
FORCE="false"
for arg in "$@"; do
  case "$arg" in
    --apply) MODE="apply" ;;
    --force) FORCE="true" ;;
    -h|--help)
      echo "Usage: $0 [--apply] [--force]"
      exit 0
      ;;
  esac
done

echo "[reorg] mode: $MODE"

# Files/directories to move
FILES=(
  main.js
  mainScreen.js
  preload.js
  webview-preload.js
  index.html
  settings.html
  settingsTranslations.js
  i18n.js
  webUITranslations.js
  update-progress.html
  update-splash.html
)
DIRS=(
  translations
)

has_changes() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if ! git diff-index --quiet HEAD --; then
      return 0
    fi
  fi
  return 1
}

if [[ "$MODE" == "apply" && "$FORCE" != "true" ]]; then
  if has_changes; then
    echo "[reorg] ⚠ Uncommitted changes detected. Commit them or pass --force."
    exit 1
  fi
fi

dest_dir="app"
echo "[reorg] create dir: ${dest_dir} (if needed)"
[[ "$MODE" == "apply" ]] && mkdir -p "$dest_dir"

mv_safe() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    echo "[reorg] move: $src -> $dst"
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p "$(dirname "$dst")"
      if command -v git >/dev/null 2>&1; then
        git mv -k "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
      else
        mv "$src" "$dst"
      fi
    fi
  else
    echo "[reorg] skip (not found): $src"
  fi
}

for f in "${FILES[@]}"; do
  mv_safe "$f" "$dest_dir/$f"
done

for d in "${DIRS[@]}"; do
  mv_safe "$d" "$dest_dir/$d"
done

# Update package.json: reset main and build.files
echo "[reorg] update: package.json (main, build.files)"

if [[ "$MODE" == "apply" ]]; then
  cp package.json package.json.bak
  node >/dev/null 2>&1 -e "process.exit(0)" || { echo '[reorg] Node.js is required.'; exit 1; }
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const pkgPath = path.resolve('package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

pkg.main = 'app/main.js';
pkg.build = pkg.build || {};

// Keep icons/**/* at the repo root
pkg.build.files = ['app/**/*', 'icons/**/*'];

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
console.log('[reorg] package.json updated');
NODE
  # Fix script reference in settings.html to relative path (if present)
  if [[ -f "app/settings.html" ]]; then
    # Use .bak for macOS/BSD sed compatibility
    sed -i.bak 's|src="settingsTranslations.js"|src="./settingsTranslations.js"|g' app/settings.html || true
  fi
else
  echo "[dry-run] package.json changes preview:" 
  echo "  - main: app/main.js"
  echo "  - build.files: ['app/**/*', 'icons/**/*']" 
fi

echo "[reorg] done. Next steps:"
echo "  1) Review dry-run log"
echo "  2) Apply: bash scripts/reorg_electron_app.sh --apply"
echo "  3) Verify app: npm start"
echo "  4) Verify packaging: npx electron-builder --dir"
