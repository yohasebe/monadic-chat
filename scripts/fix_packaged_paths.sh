#!/usr/bin/env bash
set -euo pipefail

# Fix Electron packaged paths and dotenv require in app/main.js
# - Dry-run by default. Apply with: bash scripts/fix_packaged_paths.sh --apply
# - Creates backup: app/main.js.bak_paths_fix

MODE="dry-run"
for arg in "$@"; do
  case "$arg" in
    --apply) MODE="apply" ;;
    -h|--help)
      echo "Usage: $0 [--apply]"
      exit 0
      ;;
  esac
done

TARGET="app/main.js"
test -f "$TARGET" || { echo "[fix] not found: $TARGET"; exit 1; }

echo "[fix] mode: $MODE"

if [[ "$MODE" == "apply" ]]; then
  cp -p "$TARGET" "${TARGET}.bak_paths_fix"
  node >/dev/null 2>&1 -e "process.exit(0)" || { echo '[fix] Node.js is required.'; exit 1; }

  node <<'NODE'
const fs = require('fs');
const path = require('path');
const file = path.resolve('app/main.js');
let src = fs.readFileSync(file, 'utf8');

// 1) dotenv: avoid relative './node_modules/dotenv'
src = src.replace("require('./node_modules/dotenv')", "require('dotenv')");

// 2) path.isPackaged -> app.isPackaged
src = src.replace(/\bpath\.isPackaged\b/g, 'app.isPackaged');

// 3) iconDir resolution (asar vs dev)
src = src.replace(
  /const\s+iconDir\s*=\s*[^\n]*\n/,
  "const iconDir = app.isPackaged\n"
  + "  ? path.join(process.resourcesPath, 'app.asar', 'icons')\n"
  + "  : path.join(__dirname, '..', 'icons');\n"
);

// 4) preload script path: always from __dirname
src = src.replace(
  /preload:\s*app\.isPackaged\s*\?\s*path\.join\(process\.resourcesPath,\s*'preload\.js'\)\s*:\s*path\.join\(__dirname,\s*'preload\.js'\),/g,
  "preload: path.join(__dirname, 'preload.js'),"
);

// 5) monadic.sh path: use extraResources 'app/docker' in packaged, '../docker' in dev
src = src.replace(
  /let\s+monadicScriptPath\s*=\s*path\.join\(__dirname,\s*'docker',\s*'monadic\.sh'\)[\s\S]*?;\n/,
  [
    "let monadicScriptPath = app.isPackaged",
    "  ? path.join(process.resourcesPath, 'app', 'docker', 'monadic.sh')",
    "  : path.join(__dirname, '..', 'docker', 'monadic.sh');",
    "monadicScriptPath = monadicScriptPath.replace(' ', \\\"\\\\ \\\" );\n"
  ].join('\n')
);

// 6) loadFile paths for local html under app/
// 6) Disable update splash logic entirely to reduce complexity
// 6-1) Remove before-quit-for-update event handler
src = src.replace(/autoUpdater\.on\('before-quit-for-update',[\s\S]*?\);/, "// update splash disabled\n");
// 6-2) Turn showUpdateSplash into a no-op
src = src.replace(/function\s+showUpdateSplash\s*\(\)\s*\{[\s\S]*?\}/, 'function showUpdateSplash() { /* disabled */ }');
src = src.replace(
  /settingsWindow\.loadFile\('settings\.html'\);/,
  "settingsWindow.loadFile(path.join(__dirname, 'settings.html'));"
);

// 7) system_defaults.json path: packaged vs dev
src = src.replace(
  /const\s+systemDefaultsPath\s*=\s*path\.join\(__dirname,\s*'docker',\s*'services',\s*'ruby',\s*'config',\s*'system_defaults\.json'\);/,
  [
    "const systemDefaultsPath = app.isPackaged",
    "  ? path.join(process.resourcesPath, 'app', 'docker', 'services', 'ruby', 'config', 'system_defaults.json')",
    "  : path.join(__dirname, '..', 'docker', 'services', 'ruby', 'config', 'system_defaults.json');"
  ].join('\n')
);

fs.writeFileSync(file, src, 'utf8');
console.log('[fix] Patched app/main.js');
NODE
else
  echo "[dry-run] Would patch: $TARGET"
  echo "  - Replace dotenv require to require('dotenv')"
  echo "  - Replace path.isPackaged with app.isPackaged"
  echo "  - Rewrite iconDir for asar/dev"
  echo "  - Fix preload paths to __dirname"
  echo "  - Fix monadic.sh path for packaged/dev"
  echo "  - Fix loadFile paths for settings/update pages"
  echo "  - Remove update splash logic (event + function)"
  echo "  - Fix system_defaults.json path for packaged/dev"
fi

echo "[fix] done. Next steps:"
echo "  1) Review changes (git diff)"
echo "  2) Apply: bash scripts/fix_packaged_paths.sh --apply"
echo "  3) Rebuild and test: SKIP_HELP_DB=true rake build:mac_arm64 && run app"
