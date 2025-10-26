# ハードコーディング監査（OpenAI&プロバイダー）

このページでは、モデル名のハードコーディングとspec駆動（SSOT）アプローチへの移行を追跡します。

最終更新：2025-09-05

## サマリー
- Responses API選択、ウェブ検索機能、推論、ツールサポート、ストリーミング、レイテンシ通知は、ハードコードされたリストではなく`model_spec.js`（SSOT）によって駆動されるようになりました。
- プロバイダー`/models`が返す非チャットSKUを非表示にするために、モデルディスカバリー用の粗い除外リストのみを意図的に保持しています。

## OpenAIヘルパー（lib/monadic/adapters/vendors/openai_helper.rb）

### 高影響アイテム（移行済み）
- Responses APIモデル検出：`ModelSpec.responses_api?`を介して`model_spec.js`（`api_type: "responses"`）から取得。
- ウェブ検索サポート：`ModelSpec.supports_web_search?`を介して`model_spec.js`（`supports_web_search`）から取得。
- 推論モデル検出：`model_spec.js`内の`reasoning_effort`の存在から取得。
- ツール機能：`model_spec.js`（`tool_capability: true/false`）から取得。
- ストリーミングサポート：`model_spec.js`（`supports_streaming: true/false`）から取得。
- スローモデル通知：`model_spec.js`（`latency_tier: "slow"`または`is_slow_model: true`）から取得。
- 冗長性サポート：`model_spec.js`（`supports_verbosity: true`）から取得。

### 設計上の残存項目
- ディスカバリー用の除外モデル：`/models`結果をフィルタリングするために、ヘルパー内に狭い部分一致拒否リストを保持しています（embeddings、TTS、moderation、realtime、legacy、images）。これはディスカバリーのみに影響；すべての機能ゲーティングはspec駆動。

## 理由
- SSOTはドリフトを削減し、アダプターを簡素化します。新しいSKUは複数のコードパスではなく、`model_spec.js`を更新することでサポートされます。
- プロバイダーがまだspecにない多くの非チャットSKUを返す可能性があるため、ディスカバリーには防御的フィルターが必要です。

## 次のターゲット
- 残りのモデル文字列ヒューリスティック（例：デバッグブランチ）を有用な場合はspecフラグに置き換える。
- 避けられない場合のみ`streaming_duplicate_fix`スタイルのフラグを追加することを検討；イベントタイプ駆動のストリーム処理を優先。
