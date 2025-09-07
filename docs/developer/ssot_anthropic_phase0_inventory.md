# SSOT適用 準備メモ（Anthropic/Claude）Phase 0: 観測・棚卸し

最終更新: 2025-09-05

## 対象
- ファイル: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- 目的: モデル名/ハードコード依存を洗い出し、model_spec.js の語彙へマッピングする。

## 既存のハードコード/分岐ポイント（要棚卸し）

1) モデル一覧のフィルタ/フォールバック
- API `/models` 結果から `"claude-2"` を除外。
- API失敗時に固定のフォールバック・モデルID配列を返却。
- 影響: 新SKU追加時に手動更新が必要。旧系の除外はSSOT/ルール化可能。
- 提案: model_spec 側に `deprecated: true` や `list_exclude: true`（発見限定）を付与。発見用の除外ルールはOpenAI同様「防御的フィルタ」扱いで最小限に。

2) Beta機能フラグの一括指定
- Header `anthropic-beta` に以下を常時付与:
  - `prompt-caching-2024-07-31`
  - `pdfs-2024-09-25`
  - `output-128k-2025-02-19`
  - `extended-cache-ttl-2025-04-11`
  - `interleaved-thinking-2025-05-14`
  - `fine-grained-tool-streaming-2025-05-14`
- 影響: モデル/アカウントで未対応のbetaが混在するリスク。
- 提案: model_specに `beta_flags: []` を持たせ、モデル/シリーズごとに許容フラグを定義。ユーティリティでヘッダ生成。

3) Streamingの既定
- `body["stream"] = true` を常時設定。
- 影響: モデル/モードにより非対応の可能性、またはJSON整形と競合するケース。
- 提案: model_specの `supports_streaming` を参照して設定。未定義時は既存挙動にフォールバック。

4) Web検索
- 判定: `websearch && ModelSpec.supports_web_search?(model)` → ネイティブWeb検索ツール（`web_search_20250305`）を注入。
- 評価: 既にSSOT化済み。良。
- 提案: capabilitiesを階層化（例: `capabilities.web_search: { type: "native"|"external"|"none", via: "tool"|"parameter" }`）。

5) Thinking（推論）
- 判定: `ModelSpec.supports_thinking?(model)` と `reasoning_effort != "none"`。
- thinking有効時:
  - `temperature = 1` 必須設定
  - `body["thinking"] = { effort, max_output_tokens, suffix }`
- 評価: 概ねSSOT化済み。良。
- 提案: `reasoning_effort`（[options, default]）の整合と、streamingとの併用可否を `constraints` に明示。

6) ツール可否/選択
- 現状: `tool_capability` による明示ゲートがない（`tools` は存在すれば通す／`tool_choice` をauto付与）。
- 影響: ツール非対応モデルにも送る可能性。
- 提案: model_spec `tool_capability` を導入し、false の場合は `tools/tool_choice` を送らない（OpenAIと同等）。

7) 画像/PDF（Vision）
- 現状: PDF/画像を受け取り、Claudeのdocument/imageブロックに変換して送信（`pdfs-2024-09-25` betaを前提）。
- 影響: モデル/アカウントで非対応の可能性。
- 提案: model_spec に `vision_capability: true/false` と `supports_pdf: true/false` を追加しゲート。

8) API/バージョン
- `anthropic-version: 2023-06-01` を固定。
- 提案: model_spec に `api_version` を持たせ、将来差し替えに備える（既定は現状維持）。

## model_spec.js に追加/整備したい語彙（Anthropic向け）
- 基本:
  - `api_version`: "2023-06-01"
  - `latency_tier`: "slow"（必要に応じて）
- 能力:
  - `supports_web_search`: true/false（既に運用）
  - `reasoning_effort`: [["minimal","low","medium","high"], default]
  - `supports_thinking`: true/false（thinking有無の短絡判定）
  - `tool_capability`: true/false
  - `supports_streaming`: true/false
  - `vision_capability`: true/false
  - `supports_pdf`: true/false
  - `supports_verbosity`: true/false（必要なら）
- beta_flags: ["prompt-caching-...", "pdfs-...", ...]
- constraints（任意）:
  - `json_mode_with_tools: "forbidden"|"buggy"` 等
  - `thinking_with_streaming: "ok"|"limited"`

## Phase 1 で置換候補（安全・最小差分）
1) `tool_capability` ゲート
- false のモデルに対しては `tools/tool_choice` を送らない。
- 影響範囲限定、回帰リスク小。

2) `supports_streaming` ゲート
- false なら `stream=false`。
- 既定は現状維持（未定義はtrue扱い or 現行値）。

3) `vision_capability`/`supports_pdf` ゲート
- false なら画像/PDFブロックを送らない（エラー返却 or UI非表示でカバー）。

4) `beta_flags` 生成
- model_spec の配列を連結して `anthropic-beta` に設定。
- 未定義時は現行の固定列挙を維持（フォールバック）。

## 既存コードの該当箇所（主要な変更ポイント）
- モデル一覧: `list_models`（claude-2除外・fallback配列）
- Web検索: `use_native_websearch` 判定（SSOT化済）+ ツール注入
- Thinking: `supports_thinking?` と `reasoning_effort` に応じた設定
- Streaming: `body["stream"] = true`（→ supports_streamingでゲート）
- ツール: `tool_choice` の付与条件（→ tool_capabilityでゲート）
- Vision: 画像/PDFのブロック注入（→ vision_capability/supports_pdfでゲート）
- Beta: `anthropic-beta` 固定列挙（→ beta_flagsで組立）

## 検証方針（最小スモーク）
- Chat/Chat Plus アプリ（websearch ON/OFF、thinking ON/OFF）で成功系の動作確認。
- 画像/PDF添付時に、非対応モデルでは明確なエラー／UI非表示になること（UI側は別タスク）。
- Streaming ON/OFF 切替の挙動確認。

## 次の一歩（提案）
- Phase 1: `tool_capability` と `supports_streaming` を spec-first 化（未定義は現行ロジック）。
- 続いて `vision_capability`/`supports_pdf`、`beta_flags` に着手。
- 変更は小さなPRに分割し、ログで分岐出所（spec/default/fallback）を観測可能にする。
