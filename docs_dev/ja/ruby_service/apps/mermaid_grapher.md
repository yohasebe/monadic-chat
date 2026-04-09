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

Mermaid GrapherとWeb Insightは同じ`.browser_session_id`ファイルを共有する。`--action start`は既存セッションを自動クリーンアップするため、アプリ切り替えは安全だが、他アプリのブラウザセッションは終了される。

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
- スクリーンショットファイルは`mermaid_preview_[タイムスタンプ].png`で命名
- ライブセッション中は最新HTMLを保持（ブラウザが表示中）、古いHTMLおよびPNGファイルは`cleanup_old_mermaid_files`でクリーンアップ
- `stop_mermaid_browser`で全`mermaid_live_*.html`および`mermaid_preview_*.png`ファイルを削除
- バリデーション用HTMLファイル（`mermaid_test_*.html`）は使用後即座にクリーンアップ

## ビジュアルセルフベリフィケーション (`_image`)

`preview_mermaid`はツールレスポンスハッシュの`_image`キーを介してスクリーンショットファイル名を返す。これによりスクリーンショットがLLMのビジョン入力に注入され、レンダリング結果を検証できる。画像はユーザーには**表示されない** — Mermaidダイアグラムはクライアント側の`MarkdownRenderer`がSVGとして直接レンダリングするため、スクリーンショットの表示は冗長となる。Web Insightが`_image`（LLMビジョン）と`gallery_html`（ユーザー表示）の両方を使用するのとは異なる。

## ラベル言語

MDSLシステムプロンプトはLLMに対し、ノードIDとクラス名には英語を使用する（Mermaidパーサーの要件）がラベルにはユーザーの言語を使用するよう指示する。これにより構文的に有効なダイアグラムでありながら、ユーザーの好む言語で読みやすいラベルが表示される。

## バリデーション

`preview_mermaid`はレンダリング前に内部で`run_full_validation`を実行。バリデーションはライブプレビューセッションとは干渉しない別のヘッドレスSeleniumセッション（インラインPython）を使用。

フォールバック順: Seleniumバリデーション → 静的構文バリデーション（Selenium利用不可時）。

## フロントエンドヘルパー

`sanitizeMermaidSource`はバックエンドの正規化を模倣するため、`<mermaid>`内のMermaidスニペットがプレビューPNG出力と一致する。バックエンドロジックを変更する場合は、フロントエンドヘルパーも更新すること。
