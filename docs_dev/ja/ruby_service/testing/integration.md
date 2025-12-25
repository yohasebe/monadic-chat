# 統合テスト

Monadic ChatのRubyサービス統合テスト構造について説明します。

## テストの場所

統合テストは `docker/services/ruby/spec/integration/` に配置されています。

## テスト構造

### Provider Matrixテスト (`provider_matrix/`)

すべてのプロバイダとアプリを検証する包括的なテストスイート：

**ファイル:** `all_providers_all_apps_spec.rb`

**目的:**
- すべてのプロバイダ × アプリの組み合わせを体系的にテスト
- AI評価（ResponseEvaluator）によるレスポンス品質の検証
- 全プロバイダでのツール呼び出し機能の確認
- レスポンス内のランタイムエラー検出

**対応プロバイダ:**
- OpenAI, Anthropic, Gemini, xAI/Grok, Mistral, Cohere, DeepSeek, Perplexity, Ollama

**実行方法:**
```bash
# 全プロバイダ
RUN_API=true bundle exec rspec spec/integration/provider_matrix/

# 特定のプロバイダ
PROVIDERS=openai,anthropic RUN_API=true bundle exec rspec spec/integration/provider_matrix/

# デバッグ出力付き
DEBUG=true PROVIDERS=openai RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

### Dockerインフラストラクチャテスト

| ファイル | 説明 |
|---------|------|
| `docker_infrastructure_spec.rb` | コンテナ通信、ヘルスチェック |
| `flask_app_client_docker_spec.rb` | Python Flaskコンテナ統合 |
| `code_interpreter_*.rb` | コンテナ内コード実行 |

### 機能別テスト

| カテゴリ | ファイル | 説明 |
|---------|---------|------|
| Jupyter | `jupyter_*.rb` | ノートブック作成、実行、高度な機能 |
| Voice | `voice_*.rb` | TTS/STT統合、ボイスチャット |
| Web | `selenium_*.rb` | ブラウザ自動化、Webスクレイピング |
| Database | `pgvector_*.rb`, `embeddings_*.rb` | ベクトルDB、埋め込み |
| WebSocket | `websocket_*.rb` | リアルタイム通信 |

### APIテスト (`api_media/`)

外部API呼び出しが必要なメディア生成テスト：

| ファイル | 説明 |
|---------|------|
| `image_generation_all_providers_spec.rb` | 各プロバイダでの画像生成 |
| `video_generation_openai_spec.rb` | 動画生成（OpenAI Sora） |
| `voice_pipeline_spec.rb` | 音声合成パイプライン |

**注意:** `RUN_MEDIA=true` 環境変数が必要です。

## ResponseEvaluator

`ResponseEvaluator`ユーティリティはAIベースのレスポンス検証を提供：

```ruby
require_relative '../../../lib/monadic/utils/response_evaluator'

RE = Monadic::Utils::ResponseEvaluator

result = RE.evaluate(
  response: "フランスの首都はパリです。",
  expectation: "AIがパリを首都として正しく特定した",
  prompt: "フランスの首都は？",
  criteria: "事実の正確性"
)

expect(result.match).to be(true)
expect(result.confidence).to be >= 0.7
```

**機能:**
- AI駆動のレスポンス検証（OpenAI APIを使用）
- 信頼度スコアリング
- 複数期待値の一括評価
- コンテキスト認識評価

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|----------|
| `RUN_API` | API依存テストを有効化 | `false` |
| `PROVIDERS` | テストするプロバイダのカンマ区切りリスト | 全設定済み |
| `RUN_MEDIA` | メディア生成テストを有効化 | `false` |
| `DEBUG` | デバッグ出力を有効化 | `false` |
| `OPENAI_API_KEY` | ResponseEvaluatorに必要 | - |

## 新規テストの追加

### Provider Matrixへのアプリ追加

`all_providers_all_apps_spec.rb`の`APP_TEST_CONFIGS`を編集：

```ruby
APP_TEST_CONFIGS = {
  # ...既存のアプリ...
  'MyNewApp' => {
    prompt: 'アプリのテストプロンプト。',
    expectation: 'AIが関連情報を返した',
    skip_ai_evaluation: false  # プロセス指向アプリの場合はtrue
  }
}
```

### プロバイダの追加

1. `PROVIDER_CONFIG`に追加：
```ruby
PROVIDER_CONFIG = {
  # ...既存のプロバイダ...
  'newprovider' => { suffix: 'NewProvider', timeout: 60 }
}
```

2. `provider_matrix_helper.rb`でツールサポートを実装

3. ヘルパーのツールサポートリストにプロバイダを追加

## ベストプラクティス

1. **寛容な期待値を使用** - 「レスポンス品質」ではなく「アプリが動作する」に焦点
2. **タイムアウトを適切に処理** - インフラ問題は失敗ではなくスキップ
3. **ランタイムエラーをチェック** - レスポンス内のRuby例外をパターンマッチ
4. **ResponseEvaluatorを使用** - 文字列マッチングではなくセマンティック検証
