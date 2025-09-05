#!/usr/bin/env bash
set -euo pipefail

# Monadic Chat: Electron ファイルの再配置スクリプト
# - 目的: ルート直下の Electron 関連ファイルを app/ に移動し、package.json を更新
# - 実行方法:
#     乾式実行: bash scripts/reorg_electron_app.sh
#     適用実行: bash scripts/reorg_electron_app.sh --apply
#     強制適用: bash scripts/reorg_electron_app.sh --apply --force
# - 影響範囲: Electron アプリ本体のみ（Docker/Ruby/テスト類は非対象）

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

# 移動対象のファイル/ディレクトリ
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
    echo "[reorg] ⚠ 未コミットの変更があります。コミットするか --force を指定してください。"
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

# package.json の更新: main と build.files を再設定
echo "[reorg] update: package.json (main, build.files)"

if [[ "$MODE" == "apply" ]]; then
  cp package.json package.json.bak
  node >/dev/null 2>&1 -e "process.exit(0)" || { echo '[reorg] Node.js が必要です。'; exit 1; }
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const pkgPath = path.resolve('package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

pkg.main = 'app/main.js';
pkg.build = pkg.build || {};

// icons/**/* はルートのまま維持
pkg.build.files = ['app/**/*', 'icons/**/*'];

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
console.log('[reorg] package.json updated');
NODE
  # settings.html 内のスクリプト参照を相対指定に修正（存在する場合のみ）
  if [[ -f "app/settings.html" ]]; then
    # macOS/BSD sed 互換のため .bak を付与
    sed -i.bak 's|src="settingsTranslations.js"|src="./settingsTranslations.js"|g' app/settings.html || true
  fi
else
  echo "[dry-run] package.json changes preview:" 
  echo "  - main: app/main.js"
  echo "  - build.files: ['app/**/*', 'icons/**/*']" 
fi

echo "[reorg] done. 次の手順:"
echo "  1) 乾式実行ログ確認"
echo "  2) 適用: bash scripts/reorg_electron_app.sh --apply"
echo "  3) 動作確認: npm start"
echo "  4) パッケージ検証: npx electron-builder --dir"
