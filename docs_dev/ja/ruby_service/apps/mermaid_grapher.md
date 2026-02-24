# Mermaid Grapher: レンダリングノート

## マルチプロバイダ対応

Mermaid GrapherはOpenAI、Claude、Gemini、Grokに対応。全プロバイダが同一のツールモジュール（`MermaidGrapherTools`）を共有し、LLM設定（プロバイダ、モデル、APIキーゲート）のみが異なる。

## ライブブラウザプレビュー (noVNC)

`preview_mermaid`は`web_navigator.py`を使用して非ヘッドレスChromeブラウザでダイアグラムをレンダリングし、noVNC（`http://localhost:7900`）で表示する。

- **初回呼び出し**: `--action start`で新規ブラウザセッションを作成し、生成したHTMLに遷移
- **2回目以降**: `--action navigate`で同一ブラウザ内のHTMLを更新
- **セッション検出**: `/monadic/data/.browser_session_id`ファイルの存在確認
- **フォールバック**: navigateが失敗（セッション期限切れ）した場合、自動的に`--action start`にフォールバック
- **スクリーンショット**: `--action screenshot`でレンダリング済みダイアグラムをPNGとして取得

Electronでは`preview_mermaid`実行時にnoVNCウィンドウが自動オープン（`websocket.js`のトリガー経由）。

セッションを終了しHTMLファイルをクリーンアップするには`stop_mermaid_browser`を呼び出す。

### VWEとのセッション共有

Mermaid GrapherとVisual Web Explorerは同じ`.browser_session_id`ファイルを共有する。`--action start`は既存セッションを自動クリーンアップするため、アプリ切り替えは安全だが、他アプリのブラウザセッションは終了される。

## Unicode正規化

Mermaid.jsはASCII矢印（`-->`）とラベル内のプレーン引用符を期待する。LLM出力には時々次のものが含まれる：

- `-`の代わりにUnicodeダッシュ（`–`、`—`、`ー`など）
- スマート引用符（`""`、`''`、`「」`）
- 全角スラッシュ（`／`）または括弧内の繰り返しの空行

検証/レンダリングの前に正規化：

- LLMから返されたHTMLエンティティをデコード
- Unicodeダッシュを`-`に置換
- スマート引用符/日本語スタイルの引用符をASCIIに変換
- `[ ... ]`内の空行を折りたたみ、改行を`\n`として書き直す

`sanitize_mermaid_code`または`sanitizeMermaidSource`に触れる場合は、これらのステップを保持すること。

## HTML埋め込み

MermaidコードをプレビューHTMLに埋め込む際、`<`、`>`、`&`のみをエスケープ。引用符はリテラルのままでラベルが正しくレンダリングされる。将来の変更はこの動作を保持する必要がある。

## HTMLファイルのライフサイクル

- プレビューHTMLファイルは`mermaid_live_[タイムスタンプ].html`で命名
- ライブセッション中は最新HTMLを保持（ブラウザが表示中）、古いファイルはクリーンアップ
- `stop_mermaid_browser`で全`mermaid_live_*.html`ファイルを削除
- バリデーション用HTMLファイル（`mermaid_test_*.html`）は使用後即座にクリーンアップ

## バリデーション

`preview_mermaid`はレンダリング前に内部で`run_full_validation`を実行。バリデーションはライブプレビューセッションとは干渉しない別のヘッドレスSeleniumセッション（インラインPython）を使用。

フォールバック順: Seleniumバリデーション → 静的構文バリデーション（Selenium利用不可時）。

## フロントエンドヘルパー

`sanitizeMermaidSource`はバックエンドの正規化を模倣するため、`<mermaid>`内のMermaidスニペットがプレビューPNG出力と一致する。バックエンドロジックを変更する場合は、フロントエンドヘルパーも更新すること。
