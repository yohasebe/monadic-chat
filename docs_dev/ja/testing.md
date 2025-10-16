# テストガイド（開発者向け）

このプロジェクトは複数のテストカテゴリを提供します。目標、場所、コマンド：

## カテゴリ

- ユニット（`spec/unit`）：
  - スコープ：小さなユーティリティ、外部副作用なしのアダプター動作。
  - コマンド：`rake spec_unit`または`rake spec`（すべてのRubyテストスイートを実行）。

- 統合（`spec/integration`）：
  - スコープ：アプリヘルパー、プロバイダー統合、実際のAPIワークフロー。
  - 実APIサブセットは`spec/integration/api_smoke`、`spec/integration/api_media`、`spec/integration/provider_matrix`配下にあります。
  - コマンド（Rake）：
    - `RUN_API=true rake spec_api:smoke` — プロバイダー全体の非メディア実APIスモーク。
    - `RUN_API=true RUN_MEDIA=true rake spec_api:media` — メディア（画像/音声）テスト。
    - `RUN_API=true rake spec_api:matrix` — プロバイダー全体の最小マトリックス。
    - `RUN_API=true rake spec_api:all` — すべての非メディアAPIテスト（+ オプションのマトリックス）。

- システム（`spec/system`）：
  - スコープ：ライブ外部APIなしのサーバーエンドポイントと高レベル動作。

- E2E（`spec/e2e`）：
  - スコープ：UI/サーバー配線とローカルワークフローのみ（デフォルトで実プロバイダーAPIなし）。
  - `RUN_API_E2E=true`でAPI呼び出しを有効化できますが、実APIカバレッジは脆弱性を減らすために意図的に`spec_api`に移動されています。

## 原則

- デフォルト：`RUN_API=true`でない限り実APIをスキップ。
- プロバイダーカバレッジ：Ollamaは必要に応じてオプトインで含まれます。その他は`~/monadic/config/env`のキーに依存します。
- APIテスト中のロギング：リクエストごとのロギングには`API_LOG=true`を設定、または`EXTRA_LOGGING=true`を使用（ロギングガイド参照）。

## 実APIスモークのデフォルト

`ProviderMatrixHelper`は、単一の開発者実行がレート制限に引っかからずにすべての主要プロバイダーを実行できるように保守的なヒューリスティックを適用します：

| プロバイダー    | タイムアウト（秒） | 最大リトライ | デフォルトQPS（≈リクエスト/秒） |
|---------------|-------------------|-------------|------------------------------|
| openai        | 45                | 3           | 0.5                          |
| anthropic     | 60                | 3           | 0.5                          |
| gemini        | 60                | 3           | 0.4                          |
| mistral       | 60                | 3           | 0.4                          |
| cohere        | 90                | 4           | 0.3                          |
| perplexity    | 90                | 4           | 0.3                          |
| deepseek      | 75                | 4           | 0.35                         |
| xai (Grok)    | 75                | 3           | 0.35                         |
| ollama        | 90                | 2           | 1.0                          |

すべての値はプロバイダーごとに上書きできます（例：`API_TIMEOUT_COHERE=120`または`API_RATE_QPS_OPENAI=0.25`）。プロバイダー固有の変数が存在しない場合、ヘルパーはグローバルノブ（`API_TIMEOUT`、`API_MAX_RETRIES`、`API_RATE_QPS`、`API_RETRY_BASE`）にフォールバックし、最終的に上記のデフォルトを使用します。

### スモークスイートの手動実行

1. `~/monadic/config/env`で実行するAPIキーをエクスポート（キーが欠落しているとヘルパーが`skip`します）。
2. オプションで`PROVIDERS=openai,anthropic`でプロバイダーを絞り込むか、プロバイダーごとのペーシングを調整（`API_TIMEOUT_<PROVIDER>`など）。
3. スイートを実行：
   ```bash
   RUN_API=true rake spec_api:all
   ```
   より高速なパスには、サブセットにスコープ（例：`rake spec_api:smoke`）。
4. 簡潔な要約については`./tmp/test_runs/latest_compact.md`をレビュー。一時的なエラーが疑われる場合は、失敗したプロバイダーを個別に再実行。

## 結果要約

- カスタムフォーマッターは`./tmp/test_runs/<timestamp>/`配下にアーティファクトを出力（デフォルトでは最新ディレクトリのみ保持）：
  - `summary_compact.md` — 短い要約（LLMフレンドリー）
  - `summary_full.md` — フィルタリングされたトレース付きの失敗/保留詳細
  - `rspec_report.json` — 機械可読
  - `env_meta.json` — envとgitメタデータ
- 最新のショートカット：
  - `./tmp/test_runs/latest`（シンボリックリンク）、`./tmp/test_runs/latest_compact.md`
- 古い実行を保持するには、スイートを実行する前に`SUMMARY_PRESERVE_HISTORY=true`（または`SUMMARY_KEEP_HISTORY=true`）を設定。このフラグがないと、以前の実行ディレクトリは自動的に削除されます。
- 最後の要約をターミナルに出力：
  - `rake test_summary:latest`

## ヒント

- 反復中の静かな出力：`SUMMARY_ONLY=1 ...`
- プロバイダーごとのサブセットを有効化：`PROVIDERS=openai,anthropic`（ヘルパー参照）。
- 一般的なテキストアプリの厳密な文字列マッチングを避ける。存在/非エラーに依存（テストはすでにこの方向に傾いています）。

## 環境変数（クイックリファレンス）

- `RUN_API`：実APIテストを有効化（APIバウンド仕様を実行するには`true`）。
- `RUN_MEDIA`：メディアテスト（画像/音声）を有効化。`RUN_API=true`と併用。
- `PROVIDERS`：実行するプロバイダーのカンマ区切りリスト（例：`openai,anthropic,gemini`）。
- `API_LOG`：テストごとのリクエスト/レスポンス要約を出力するには`true`。
- `API_TIMEOUT`：リクエストごとのタイムアウト（秒）（Rake経由のデフォルト：非メディア90、メディア120）。
- `API_MAX_RETRIES`：一時的なエラーのリトライ（余分なコストを避けるため、デフォルトは`0`）。
- `API_RATE_QPS`：テスト全体でスロットル（例：`0.5`で約2秒間隔）。
- プロバイダー固有のオーバーライドは同じパターンを継承：`API_TIMEOUT_<PROVIDER>`、`API_MAX_RETRIES_<PROVIDER>`、`API_RATE_QPS_<PROVIDER>`、`API_RETRY_BASE_<PROVIDER>`（プロバイダー名は大文字、例：`API_TIMEOUT_GEMINI`）。
- `SUMMARY_ONLY`：進捗出力+最終要約を使用するには`1`。アーティファクトは引き続き生成されます。
- `SUMMARY_RUN_ID`：複数の実行を1つのアーティファクトディレクトリに照合するための固定ID。
- プロバイダー固有（オプション）：
  - `GEMINI_REASONING` / `REASONING_EFFORT`：Geminiの推論レベル（必要でない限り省略）。
  - `GEMINI_MAX_TOKENS` / `API_MAX_TOKENS`：出力トークンの上限。
  - `API_TEMPERATURE`：model_specが許可する場合のみ設定。そうでなければ未設定のままにします。
  - `INCLUDE_OLLAMA`：デフォルトでプロバイダーリストにOllamaを含めるには`true`。
