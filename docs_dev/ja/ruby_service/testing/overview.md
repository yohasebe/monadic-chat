# Monadic Chat Ruby テスト

このディレクトリには、Monadic ChatのRubyコンポーネントのテストが含まれています。

## テスト構造

テストスイートは次のように整理されています：

- `spec_helper.rb` - すべてのテストの共通セットアップとヘルパーユーティリティ
- `*_spec.rb` - 異なるコンポーネントの個別テストファイル
- `monadic_app_command_mock.rb` - コマンド実行テスト用のMonadicAppのモック実装

## 共有テストユーティリティ

コードの再利用と一貫性を向上させるために、いくつかの共有テストユーティリティを実装しました：

1. **TestHelpers モジュール** - すべてのテストの共通ヘルパーメソッド：
   - `mock_successful_response` - 標準的な成功HTTPレスポンスを作成
   - `mock_error_response` - 標準的なエラーHTTPレスポンスを作成
   - `mock_status` - コマンドステータス用の標準OpenStructを作成
   - `stub_http_client` - 標準HTTPクライアントモックをセットアップ

2. **共有例**：
   - `"a vendor API helper"` - すべてのベンダーAPIヘルパーの標準テスト
   - `"command execution"` - コマンド実行シナリオの標準テスト

## テスト対象の主要コンポーネント

1. **コマンド実行**
   - `bash_command_helper_spec.rb` - コマンド実行機能を提供するMonadicHelperモジュールのテスト
   - `monadic_app_command_spec.rb` - コマンド実行に関連するMonadicAppクラスメソッドのテスト

2. **テキスト処理**
   - `pdf_text_extractor_spec.rb` - PDF抽出のテスト
   - `string_utils_spec.rb` - 文字列ユーティリティ関数のテスト

3. **API統合**
   - `interaction_utils_spec.rb` - APIインタラクションのテスト
   - `flask_app_client_spec.rb` - Flask APIクライアントのテスト
   - `embeddings_spec.rb` - ベクトル埋め込みのテスト
   - `websocket_spec.rb` - WebSocket機能のテスト

4. **ベンダーヘルパー**
   - `claude_helper_spec.rb` - Claude API統合のテスト
   - `cohere_helper_spec.rb` - Cohere API統合のテスト
   - `gemini_helper_spec.rb` - Google Gemini API統合のテスト
   - `openai_helper_spec.rb` - OpenAI API統合のテスト
   - `mistral_helper_spec.rb` - Mistral API統合のテスト
   - `perplexity_helper_spec.rb` - Perplexity API統合のテスト

5. **思考/推論プロセス表示**
   - `openai_reasoning_spec.rb` - OpenAI o1/o3推論コンテンツ抽出のテスト
   - `claude_thinking_spec.rb` - Claude Sonnet 4.5+思考コンテンツブロックのテスト
   - `deepseek_reasoning_spec.rb` - DeepSeek reasoner/r1推論コンテンツのテスト
   - `gemini_thinking_spec.rb` - Gemini 2.0思考モードと思考パーツのテスト
   - `grok_reasoning_spec.rb` - Grok推論コンテンツ抽出のテスト
   - `mistral_reasoning_spec.rb` - Mistral推論コンテンツ抽出のテスト
   - `cohere_thinking_spec.rb` - Cohere思考コンテンツ（JSON形式）のテスト
   - `perplexity_thinking_spec.rb` - Perplexityデュアル形式思考（JSON + タグ）のテスト

## テスト設計原則

1. **分離** - 異なるテストファイル間の競合を避けるために名前空間を使用
2. **モック** - 外部サービス呼び出しを避けるために依存関係をモック
3. **共有ユーティリティ** - 共通テストコードをヘルパーモジュールと共有例に抽出
4. **包括的カバレッジ** - エッジケースとエラー条件をテスト

## テストの実行

すべてのテストを実行：
```
bundle exec rspec spec
```

特定のテストファイルを実行：
```
bundle exec rspec spec/bash_command_helper_spec.rb
```

## コマンドテストのテスト構造

コマンド実行テストは、アプリケーション全体をロードしないように構造化されています。
`monadic_app_command_mock.rb`で名前空間化されたMonadicAppのモックバージョンを作成し、
コマンド実行機能をテストするのに十分な機能のみを提供します。

### 名前空間構造

- `MonadicAppTest` - コマンドテストのメイン名前空間
  - `MonadicHelper` - ヘルパーモジュールのモック実装
  - `MonadicApp` - アプリクラスのモック実装

このアプローチにより、すべてのテストを一緒に実行する際に実際のMonadicAppクラスとの競合を防ぎます。
