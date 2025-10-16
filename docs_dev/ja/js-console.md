# JavaScript コンソールログモード（開発者向け）

Monadic Chatは開発中にログを観察するための2つの主要な場所を提供します：

- Electron DevTools コンソール — Electronウィンドウの標準ブラウザコンソール
- コンソールパネル（アプリコンソール） — `docs/basic-usage/console-panel.md`で説明されているアプリ内コンソール

## Electron DevTools

- Electronウィンドウで`Cmd/Ctrl+Shift+I`で開く
- ネットワーク/API詳細は、Extra Loggingが有効な場合に表示される（Logging Guide参照）
- `app/main.js`では、Electronランタイムログフラグは本番環境のノイズ制御のためにデフォルトで無効化されている：
  - `process.env.ELECTRON_ENABLE_LOGGING = '0'`
  - `process.env.ELECTRON_DEBUG_EXCEPTION_LOGGING = '0'`
  深いデバッグのために、`electron .`を実行する前にこれらを`'1'`に設定することで一時的に有効にできる

## アプリコンソールパネル

- ユーザーレベルの操作については`docs/basic-usage/console-panel.md`を参照
- 開発者として、開発中にここで起動、コンテナオーケストレーション、サーバーログを監視できる
- メニュー → 開く → ログフォルダを開く で`~/monadic/log`にジャンプ（Logging Guide参照）

## きめ細かいデバッグカテゴリ

- 統合されたデバッグカテゴリは`~/monadic/config/env`で制御可能：
  - `MONADIC_DEBUG=api,embeddings`（カンマ区切り）
  - `MONADIC_DEBUG_LEVEL=debug`（none、error、warning、info、debug、verbose）
- デバッグ実行（`rake server:debug`）では、`EXTRA_LOGGING`は強制的にtrueになる
