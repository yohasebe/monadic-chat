**SSOT正規化とアクセサー（内部向け）**

このドキュメントは、モデル機能のサーバー側正規化レイヤーと正規アクセサーについて説明します。Monadic Chatコントリビューターが、後方互換性を維持しながらプロバイダー全体で単一の語彙を維持するのに役立ちます。

**目標**
- `model_spec.js`（SSOT）で機能セマンティクスを一元化。
- ヘルパーでハードコードされたモデルリスト/正規表現を避ける。仕様フラグを優先。
- プロバイダー固有のエイリアスを正規名にマッピングする正規化パスを提供。
- 保守的なデフォルトで安定したアクセサーを提供。

**正規化（ModelSpec.normalize_spec）**
- ベース仕様ロードとユーザーオーバーライドマージ後に実行。
- 元のものを削除せずに、エイリアスを正規プロパティに変換：
  - `reasoning_model` → `is_reasoning_model`
  - `websearch_capability` / `websearch` → `supports_web_search`
  - `is_slow_model` → `latency_tier: "slow"`
  - `responses_api: true` → `api_type: "responses"`
- `supports_pdf_upload`を自動入力しません（動作変更を避けるためにモデルごとに明示的）。

**正規アクセサー**
- 生の`get_model_property`呼び出しよりもこれらを優先：
  - `tool_capability?(model)`：非false → true
  - `supports_streaming?(model)`：nil→true、それ以外はブール値
  - `vision_capability?(model)`：nil→true、それ以外はブール値
  - `supports_pdf?(model)`：ブール値
  - `supports_pdf_upload?(model)`：ブール値
  - `supports_web_search?(model)`：ブール値
  - `responses_api?(model)`：ブール値

**ヘルパーガイドライン**
- ストリーミング：`supports_streaming?`でゲート。未定義の場合はデフォルトでtrue。
- ツール：`tool_capability?`でゲート。falseの場合は`tools/tool_choice`をドロップ。
- ビジョン/PDF：コンテンツパーツを組み立てる前に検証。URLのみのPDFの場合、base64を添付する代わりに明確なエラーを返す（またはユーザーに指示）。
- 推論：該当する場合は`is_reasoning_model`/`reasoning_effort`を使用。モデル名の文字列マッチングを避ける。
- Web検索：ハードコードされたリストの代わりに`supports_web_search?`（およびプロバイダーのネイティブ設定）を使用。
- 監査：`EXTRA_LOGGING`が有効な場合、ソース（spec/fallback/legacy）を含む単一行の機能サマリーをログ出力。

**UIガイダンス（クロスチーム）**
- ファイル添付ボタンはアプリ機能 + `vision_capability`によって制御されます。
- `supports_pdf_upload: true`の場合のみ「Image/PDF」を表示。それ以外は「Image」を表示。
- URLのみのPDFモデル（`supports_pdf: true`、`supports_pdf_upload: false`）を一貫して保つ：ファイル入力で`.pdf`を許可しない。

**移行計画**
- 新しいヘルパーは最初からアクセサーを使用する必要があります。
- 既存のヘルパーは段階的に移行できます：
  1) ハードコードされたリストをアクセサーに置き換える
  2) 機能監査行を追加
  3) 安定化後にデッド/レガシーコードパスを削除

**テスト**
- 以下のユニットテストを追加：
  - 正規化マッピング（エイリアス → 正規）
  - アクセサーデフォルト（nil → 期待されるデフォルト）
  - URLのみのPDF（Perplexity）vsファイルアップロード（Claude/Gemini/OpenAI）の動作
- システムテストでは、ボタンラベル/accept属性がSSOTフラグを反映していることを検証。
