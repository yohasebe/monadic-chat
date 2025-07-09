# Monadic DSLの内部実装

?> このドキュメントはMonadic DSL (MDSL)の内部実装について詳細な説明を提供します。MDSLの内部動作を理解したい開発者や、その開発に貢献したい方向けの内容です。

## 1. 概要

Monadic DSL (MDSL)は、プロバイダーの違いを抽象化し、宣言的な構文を提供することで、AIアプリケーション開発を簡素化するRubyベースのドメイン特化言語です。

### 1.1 コアアーキテクチャ

#### 1.1.1 プロバイダー抽象化
MDSLは統一されたインターフェースを通じて複数のLLMプロバイダーをサポートします：
- **OpenAI** - [https://openai.com](https://openai.com)
- **Anthropic** (Claude) - [https://anthropic.com](https://anthropic.com)
- **Google** (Gemini) - [https://ai.google.dev](https://ai.google.dev)
- **Mistral** - [https://mistral.ai](https://mistral.ai)
- **Cohere** - [https://cohere.com](https://cohere.com)
- **DeepSeek** - [https://deepseek.com](https://deepseek.com)
- **Perplexity** - [https://perplexity.ai](https://perplexity.ai)
- **xAI** (Grok) - [https://x.ai](https://x.ai)
- **Ollama** - [https://ollama.ai](https://ollama.ai)

#### 1.1.2 重要な命名規則
?> **重要**: MDSLアプリ名はRubyクラス名と正確に一致する必要があります。例えば、`app "ChatOpenAI"`は対応する`class ChatOpenAI < MonadicApp`が必要です。これにより適切なメニューグループ化と機能が保証されます。

#### 1.1.3 ファイル構成
```
apps/
├── chat/
│   ├── chat_openai.mdsl
│   ├── chat_openai.rb
│   └── chat_tools.rb
└── second_opinion/
    ├── second_opinion_openai.mdsl
    ├── second_opinion_tools.rb
    └── ...
```

### 1.2 主要な設計原則

1. **宣言的構文** - 実装の詳細なしでアプリを定義
2. **プロバイダー独立性** - 最小限の変更でプロバイダーを切り替え
3. **ツールフォーマット統一** - すべてのプロバイダー固有フォーマットに対して単一の構文
4. **ランタイムクラス生成** - DSLを動的にRubyクラスに変換
5. **モナディックエラー処理** - 明示的で連鎖可能なエラー管理

## 2. DSL構造と処理

### 2.1 基本的なアプリ定義
```ruby
app "AppNameProvider" do
  description "簡潔な説明"
  icon "fa-icon"
  
  llm do
    provider "provider_name"
    model "model_name"
  end
  
  features do
    # 機能フラグ
  end
  
  tools do
    # ツール定義
  end
  
  system_prompt "..."
end
```

### 2.2 読み込みプロセス
1. **ファイル検出** - `.mdsl`拡張子または`app "Name" do`パターン
2. **コンテンツ評価** - DSLは安全なコンテキストで`eval`により評価
3. **状態構築** - 設定は`AppState`に収集
4. **クラス生成** - 動的なRubyクラス作成
5. **モジュール包含** - プロバイダー固有のヘルパーを含む

### 2.3 プロバイダー設定
```ruby
PROVIDER_INFO = {
  "openai" => {
    helper_module: "OpenAIHelper",
    default_model: "gpt-4.1-mini",
    features: { monadic: true }
  },
  "anthropic" => {
    helper_module: "ClaudeHelper", 
    default_model: "claude-3-5-sonnet-20241022",
    features: { toggle: true, initiate_from_assistant: true }
  },
  # ... 他のプロバイダー
}
```

## 3. 機能管理

### 3.1 プロバイダー固有の機能
- `monadic` - JSON状態管理（すべてのプロバイダーで対応）
- `toggle` - 折りたたみ可能なUIセクション（Claude/Gemini/Mistral/Cohere）
- `initiate_from_assistant` - AIメッセージで開始（Claude、Gemini）

?> **重要**: `monadic`と`toggle`を両方有効にしないでください - これらは相互排他的です。

### 3.2 モデル固有の動作
- **推論モデル** - o1、o3は温度調整をサポートしません
- **思考型モデル** - Gemini 2.5は温度の代わりに`reasoning_effort`を使用
- **ウェブ検索フォールバック** - 推論モデルはウェブクエリに`WEBSEARCH_MODEL`を使用

## 4. ツールシステム

### 4.1 統一されたツール定義
```ruby
tools do
  define_tool "tool_name", "ツールの説明" do
    parameter :param_name, "type", "説明", required: true
  end
end
```

### 4.2 プロバイダーフォーマッタ
各プロバイダーには、抽象定義を変換する専用フォーマッタがあります：

```ruby
FORMATTERS = {
  openai: ToolFormatters::OpenAIFormatter,
  anthropic: ToolFormatters::AnthropicFormatter,
  gemini: ToolFormatters::GeminiFormatter,
  # ... 他のプロバイダー
}
```

## 5. ランタイム動作

### 5.1 クラス生成
MDSLは動的にRubyクラスを生成します：
```ruby
class AppNameProvider < MonadicApp
  include ProviderHelper
  
  @settings = { /* DSLから */ }
  @app_name = "AppNameProvider"
  
  # ファサードモジュールからツールメソッドを含む
end
```

### 5.2 エラー処理
連鎖可能なエラー処理のためにモナディックパターンを使用：
```ruby
Result.new(value)
  .bind { |v| validate(v) }
  .map { |v| transform(v) }
  .bind { |v| save(v) }
```

## 6. 一般的な問題

1. **メニューグループの問題** - アプリ名がクラス名と一致しているか確認
2. **モデルが見つからない** - ヘルパーの`list_models`が`$MODELS`キャッシュを使用しているか確認
3. **ツールが見つからない** - ファサードモジュールが含まれているか確認
4. **機能の競合** - `monadic`/`toggle`の排他性を確認

?> **デバッグのために**: 問題のトラブルシューティング時には、コンソールパネルの設定で「Extra Logging」を有効にして詳細なログを取得してください。


## 7. ベストプラクティス

1. **命名規則に従う** - アプリ識別子はクラス名と一致する必要があります
2. **ファサードパターンを使用** - ツールを別の`*_tools.rb`ファイルに実装
3. **機能制約を尊重** - 互換性のない機能を混在させない
4. **複数のプロバイダーでテスト** - 移植性を確保
5. **エラーを適切に処理** - モナディックパターンを使用

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - ユーザー向けDSLドキュメント
- [アプリの開発](./develop_apps.md) - アプリ開発ガイド
- [設定項目](./setting-items.md) - 設定リファレンス
