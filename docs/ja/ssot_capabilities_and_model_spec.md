**SSOT（Single Source of Truth）概要**
- モデル機能の一次情報は `public/js/monadic/model_spec.js` に集約されています。
- UI とサーバーヘルパーはこの Spec を参照して、各プロバイダーで機能を一貫して有効/無効にします。
- `~/monadic/config/models.json` を用意すると、モデル定義を追加/上書きできます（実行時にマージ）。

**主なプロパティ（正規語彙）**
- api_type: API種別（例: "responses"）。
- tool_capability: ツール実行（関数呼び出し）可否。
- supports_streaming: ストリーミング（SSE）可否。
- vision_capability: 画像入力可否。
- supports_pdf: PDF機能の有無（一般能力）。
- supports_pdf_upload: PDFファイルのアップロード可否（false の場合は URL のみ）。
- supports_web_search: ネイティブWeb検索の有無。
- is_reasoning_model: 推論（thinking）モデルかどうか。
- reasoning_effort / supports_thinking / thinking_budget: 思考出力の制御（ベンダ依存）。
- latency_tier: レイテンシ目安（UI表示向け）。

**UIの動作（ボタンと入力）**
- 画像/PDF 添付ボタンが表示される条件：
  - アプリ側で画像機能が有効、かつ
  - 選択モデルの `vision_capability: true`。
- ボタンの文言と受け付け拡張子：
  - `supports_pdf_upload: true` → 「画像/PDF」（.pdf 受け付け）
  - それ以外 → 「画像」（.pdf は受け付けない）
- URL限定のPDF（例: Perplexity）の場合：ファイルではなく、メッセージ本文に公開URLを貼ってください。

**プロバイダー別の例**
- Perplexity: `supports_pdf: true` かつ `supports_pdf_upload: false`（PDFはURLのみ）。画像はURLで可。
- Cohere: PDFアップロード非対応（他プロバイダーの利用や本文貼り付けを検討）。
- Claude/Gemini/OpenAI: PDF/画像の対応は Spec に従い、UI/サーバが機能を制御します。

**モデルの追加/上書き**
- `~/monadic/config/models.json` を作成し、正規語彙でプロパティを定義してください。
- 実行時に既定の `model_spec.js` とマージされます。

**トラブルシューティング**
- 添付ボタンが出ない → アプリの画像機能、`vision_capability`、`supports_pdf_upload` を確認。
- PDFアップロードが拒否される → URLのみ対応の可能性（`supports_pdf_upload` を確認）。
- `EXTRA_LOGGING` を有効にすると、サーバーログに能力監査（一行）を出力します。

**アプリ開発者向けの指針**
- モデル名のハードコーディングは避け、Spec のフラグ（`tool_capability`, `supports_streaming` など）に基づいて機能を切り替えてください。
- UI/サーバーともに SSOT を信頼し、アプリ定義は最小限のオプションに留めると保守性が上がります。

