# SSOT拡張計画（OpenAI以外の各プロバイダへ適用）

最終更新: 2025-09-05

## 目的
- モデル能力・制約・推奨パラメータの「単一の真実の源（SSOT）」を `model_spec.js` に集約し、各ベンダーヘルパーのハードコードやモデル名ヒューリスティックを段階的に削減する。
- 既にOpenAIで進めた方針（Responses API判定、web検索、reasoning、tool可否、streaming可否、遅延通知、verbosityなど）を、他プロバイダにも安全に横展開する。

## 適用範囲（優先順）
1. Anthropic（Claude）
2. Google（Gemini）
3. Cohere
4. xAI（Grok）
5. Mistral
6. Perplexity
7. DeepSeek
8. Ollama（含むが、ローカル/可用性の都合で後段）

## 現状の問題（よくあるパターン）
- ベンダーヘルパー内にモデル名やパターン（`include?("sonnet")` 等）での分岐が残っている。
- ベンダー固有のエンドポイント選択や未対応パラメータの無効化が、SSOTではなく各所の条件分岐で実装されている。
- 仕様差分（tool/JSON/streaming/visionなど）の扱いが分散し、追加SKU対応やドキュメント同期が重い。

## 目標（OpenAIでの成果を各社に展開）
- 機能判定を `model_spec.js` に移す：
  - `api_type`（responses/chat/completions 等）
  - `supports_web_search`
  - `reasoning_effort`（配列: [options, default]）
  - `tool_capability`（true/false）
  - `supports_streaming`（true/false）
  - `vision_capability`（true/false）
  - `supports_verbosity`（true/false）
  - `latency_tier`（"slow" など）
- ベンダーヘルパーは「輸送＋最小の癖対応」に縮退（例: メッセージshapeやエラー正規化）。

## ベンダー別の着手ポイントと移行方針

### Anthropic（Claude）
- ファイル: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- 代表的なハードコード例（想定）:
  - thinking/sonnet/oplus系列の判定、JSONモード可否、tool呼び出し数制限など。
- 移行:
  - `reasoning_effort` または `supports_thinking` をspecに定義し、`supports?(:thinking)` 相当のゲートで制御。
  - `tool_capability`/`supports_streaming`/`vision_capability` をspec化。
  - エンドポイント・パラメータ（`system`→`developer`相当など）は正規化レイヤで共通化。

### Google（Gemini）
- ファイル: `.../vendors/gemini_helper.rb`
- 着点:
  - contents/parts 形のメッセージ変換、function_declarations、画像入力/出力の扱い。
- 移行:
  - `vision_capability`/`tool_capability`/`supports_streaming` をspec化。
  - 画像/ファイル入力の上限・併用制約を `constraints` に集約（例: tool+json 同時不可等）。

### Cohere
- ファイル: `.../vendors/cohere_helper.rb`
- 着点:
  - v2 typed partsのshape、reasoning相当の可否、JSON/ツール対応の差。
- 移行:
  - `tool_capability`/`supports_streaming`/`vision_capability`/`reasoning_effort`（対応する場合）をspec化。

### xAI（Grok）
- ファイル: `.../vendors/grok_helper.rb`
- 着点:
  - websearchのネイティブパラメータ、画像入力モデルの型、streamingイベントのバリエーション。
- 移行:
  - `supports_web_search`/`vision_capability`/`supports_streaming` をspec化。

### Mistral
- ファイル: `.../vendors/mistral_helper.rb`（存在する場合）
- 着点:
  - Chat/Tool/Streamingの有無、モデル系列（large/small/mini）での差。
- 移行:
  - `tool_capability`/`supports_streaming` をspec化。必要なら `latency_tier`。

### Perplexity
- ファイル: `.../vendors/perplexity_helper.rb`
- 着点:
  - 検索内蔵/外部検索の区別、長文/streamingの仕様差。
- 移行:
  - `supports_web_search` をspec化。web検索は provider内蔵/外部ツールの区別を `capabilities.web_search.via` 等に拡張可。

### DeepSeek
- ファイル: `.../vendors/deepseek_helper.rb`
- 着点:
  - thinking/推論系の扱い、streaming差分、画像可否。
- 移行:
  - `reasoning_effort`/`supports_streaming`/`vision_capability` をspec化。

### Ollama
- 着点:
  - ローカル実行でのモデル多様性、API互換のばらつき。
- 移行:
  - `tool_capability`/`supports_streaming` をspec化（可用性に応じて段階的適用）。

## 共通の実装ガイド
1. ModelSpecユーティリティの拡張（Ruby）
   - `responses_api?(model)`（済）
   - `supports_web_search?(model)`（済）
   - `model_has_property?(model, "reasoning_effort")`（済）
   - `get_model_property(model, key)`（済）
   - 必要に応じて `supports_streaming?(model)` などシンタ糖を追加
2. 正規化レイヤ
   - メッセージshape（OpenAI messages / Gemini contents / Cohere typed parts / xAI array）への変換をユーティリティ化
   - 未対応パラメータの除去・クランプ（`accepts`／`constraints` を仕様化できるとベター）
3. レスポンス/エラー正規化
   - 成功: `text`, `tool_calls`, `images`, `meta` の共通化
   - 失敗: `Timeout`, `RateLimited`, `Validation`, `UnsupportedFeature`, `Parsing` 等
4. ドキュメントとログ
   - 仕様の拡張（`model_spec.js`）時は Developer Docs に追記
   - EXTRA_LOGGING時に「適用能力」「無効化パラメータ」「選択エンドポイント」を簡潔に記録

## フィードバック反映（設計強化）
- 能力スキーマの階層化（例）
  - capabilities.web_search:
    - type: "native" | "external" | "none"
    - via: "parameter" | "tool" | "embedded"
  - capabilities.thinking:
    - type: "reasoning_effort" | "thinking_budget" | "custom"
    - format: "structured" | "freeform"
- バージョン管理の付帯情報（必要に応じて）
  - api_version: プロバイダAPIの仕様バージョン
  - spec_version: 当該エントリのスキーマ版
  - deprecated_after: 廃止予定日
- フォールバック戦略（3段階）
  1) model_spec.js から取得
  2) PROVIDER_DEFAULTS（プロバイダ既定）
  3) 安全側デフォルト（無効化／非対応）
- 緊急時オーバーライド（任意）: 例として Claude では `CLAUDE_LEGACY_MODE=true` で一時的に streaming/tools/vision/pdf を許可するガードを実装。段階導入時の回帰時に切り戻しが可能。
  - テスト観点（後続）: `CLAUDE_LEGACY_MODE` を有効化した場合に全能力が上書きされることを 1 ケースで検証（環境変数の前後で `supports_streaming`/`tool_capability`/`vision_capability`/`supports_pdf` が true になる）。
- 監視とロールバック
  - CAPABILITY_AUDIT=1 で「どの能力をどの出所（spec/default/fallback）で判定したか」をログ
  - 環境変数で旧ロジックに切り戻すガードを用意（段階導入時）
- 移行ダッシュボード（任意）
  - providerごとに機能の移行状態を簡易YAML/JSONで可視化（spec_driven/hybrid/legacy）

## 段階的移行（小さく安全に）
- Phase 0（観測）:
  - 各ヘルパーのモデル名分岐を棚卸し（`rg`で列挙）し、対応する能力語彙に落とし込む
- Phase 1（spec-first, fallback併用）:
  - 置換対象を1つに限定（例: `tool_capability` だけspecに寄せる）
  - ヘルパーは `ModelSpec.get_model_property(model, "tool_capability")` を優先
  - specが未定義のモデルのみ従来ロジックにフォールバック
- Phase 2（正規化導入）:
  - メッセージ変換/パラメータ正規化を共通化し、各ヘルパーから呼び出す
- Phase 3（リスト撤廃）:
  - specカバレッジが揃い次第、旧リスト/ヒューリスティックを削除
- Phase 4（契約テスト）:
  - specの有無で期待動作を検証（例: `tool_capability: false` のモデルにtoolsを送らない）

## テスト強化（spec駆動の自動チェック）
- ModelSpec compliance（例）
  - tool_capability=false のモデルに tools を送らない
  - supports_streaming=false のモデルで stream=false 強制
  - supports_web_search=true のモデルで web 検索注入が有効
  - reasoning_effort の有無でパラメータ付与/削除が一致

## リスクと対策
- 仕様不足: 既存分岐の暗黙知がspecに未反映 → 観測ログ＋フォールバックで段階導入
- タイミング競合（UI）: モデル/アプリ選択の順序・非同期 → 末尾トリガ/ヘルパー集約（今回の修正方針）
- コスト/遅延: streaming/検索の誤判定 → specで`supports_streaming`/`supports_web_search`を必ず更新

## 受け入れ基準（各ベンダー共通）
- 主要アプリ（Chat/Chat Plus/Code Interpreter/Research Assistantなど）で、従来挙動からのレグレッションなし
- 仕様更新のみで新SKUを有効化できる（ヘルパー未改変）
- ログ/テストでspec駆動の分岐が確認できる

## 作業リストのひな形（例）
- Claude: `tool_capability`/`supports_streaming` をspec化→ヘルパー置換→軽いスモーク
- Gemini: `vision_capability`/`tool_capability`/`supports_streaming` をspec化→置換
- Cohere: `tool_capability`/`supports_streaming` 置換、typed parts 正規化の共通化
- xAI: `supports_web_search`/`vision_capability`/`supports_streaming` 置換
- Mistral/Perplexity/DeepSeek/Ollama: 同上（段階）

## 優先順位（改訂提案）
1. Anthropic（人気・中程度の複雑性）
2. Gemini（人気・やや複雑）
3. DeepSeek（シンプル）
4. Cohere（中程度）
5. xAI（中程度）
6. Mistral（複雑）
7. Perplexity（特殊）
8. Ollama（最特殊）

## 参照ファイル
- model_spec: `docker/services/ruby/public/js/monadic/model_spec.js`
- ModelSpecユーティリティ: `docker/services/ruby/lib/monadic/utils/model_spec.rb`
- 各ベンダーヘルパー: `docker/services/ruby/lib/monadic/adapters/vendors/*_helper.rb`
- UIユーティリティ/選択制御: `docker/services/ruby/public/js/monadic/*.js`

---
この計画は「安全第一・小さく導入」を前提にしています。まずは各ベンダーで1つの能力（例: tool_capability）からspec駆動へ寄せ、成功体験を積みながら正規化・撤廃の射程を広げるのが最短・最安です。

## 次の一歩（提案）
- Phase 0: Anthropic のヘルパーから `tool_capability` のみ specファースト化（未定義は旧ロジック）
- Phase 1: `supports_streaming` を追加 → ヘルパー置換（未定義は旧ロジック）
- ここまでで小さくPRを分割し、spec駆動テスト（最低限）を追加して回帰を防止
