# モデル仕様正規語彙（SSOT）

このドキュメントは、`model_spec.js`でプロバイダー間で使用される正規プロパティ名と、サーバー（`ModelSpec`ユーティリティ）によってエイリアスがどのように正規化されるかを定義します。プロバイダーは追加のベンダー固有フィールド（例：Anthropicの`beta_flags`）を公開することができますが、該当する場合は以下の語彙を優先する必要があります。

## 正規プロパティ

- api_type: string
  - 値: "responses"（OpenAI Responses API）。オプション。

- tool_capability: boolean
  - モデルがツール/関数呼び出しを実行できるかどうか。

- supports_streaming: boolean
  - SSE/ストリーミングがサポートされているかどうか。未定義の場合、ヘルパーではtrueがデフォルト。

- vision_capability: boolean
  - モデルが画像入力を受け付けるかどうか。未定義の場合、ヘルパーではtrueがデフォルト。

- supports_pdf: boolean
  - モデルが一般的にPDFをサポートするかどうか。UIはファイルピッカーの状態を決定するために`supports_pdf_upload`が必要な場合があります。

- supports_pdf_upload: boolean
  - モデルがPDFファイルのアップロードを受け付けるかどうか。falseで`supports_pdf`がtrueの場合、URLのみを使用（例：Perplexityでは`pdf_url`経由）。

- supports_web_search: boolean
  - モデルがネイティブなウェブ検索機能を持つかどうか。

- is_reasoning_model: boolean
  - モデルが推論/思考モデルかどうか。

- reasoning_effort: [ [options], default ]
  - 例: [["minimal","low","medium","high"], "low"]。

- supports_thinking: boolean
  - プロバイダーが専用の思考/思考予算機能をサポートするかどうか。

- thinking_budget: object
  - 構造: { min, max, can_disable, presets: { minimal, low, medium, high } }。

- latency_tier: string
  - 値: "slow" | "normal"（自由形式）。UIはこれを使用して通知を表示することができます。

- supports_parallel_function_calling: boolean
  - オプション。プロバイダー固有の並列ツールセマンティクス。

- beta_flags: string[]
  - Anthropic専用（例：`anthropic-beta`ヘッダー）。プロバイダー固有として保持。

- api_version: string
  - プロバイダー固有のバージョンタグ付け（例：Anthropicの"2023-06-01"）。

## エイリアス正規化

サーバーは元のエイリアスを削除せずに、正規プロパティに正規化します。これにより、ヘルパーに単一の語彙を提供しながら、後方互換性を確保します。

- reasoning_model -> is_reasoning_model
- websearch_capability / websearch -> supports_web_search
- is_slow_model -> latency_tier: "slow"
- responses_api (true) -> api_type: "responses"

注意：動作変更を避けるため、`supports_pdf_upload`は自動入力されません。必要に応じてモデルごとに明示的に設定してください（例：Perplexity: `supports_pdf: true`, `supports_pdf_upload: false`）。

## アクセサー（サーバー）

ヘルパーは可能な限り、生のプロパティを読み取る代わりにアクセサーを優先する必要があります：

- ModelSpec.tool_capability?(model)
- ModelSpec.supports_streaming?(model)
- ModelSpec.vision_capability?(model)
- ModelSpec.supports_pdf?(model)
- ModelSpec.supports_pdf_upload?(model)
- ModelSpec.supports_web_search?(model)
- ModelSpec.responses_api?(model)

これらのアクセサーは、既存のヘルパーの動作に沿って保守的なデフォルト（例：未定義の場合、ストリーミングはtrueがデフォルト）を適用します。

## UIガイダンス

- 画像/PDFボタン
  - アプリが画像をサポートし、`vision_capability`がtrueの場合にボタンを表示。
  - `supports_pdf_upload`がtrueの場合、「画像/PDF」としてラベル付けし、ファイル入力で`.pdf`を許可。
  - それ以外の場合、「画像」としてラベル付けし、`.pdf`を許可しない。
  - URLのみのPDF（例：Perplexity）の場合、`supports_pdf_upload: false`を保持し、メッセージにPDF URLを含めるようユーザーに指示。

## モデルの追加

新しいモデルSKUを追加する場合、`model_spec.js`でこの正規語彙を優先してください。プロバイダーが追加フィールドを公開する場合、それらをベンダースコープとして保持し、必要に応じてドキュメント化してください。
