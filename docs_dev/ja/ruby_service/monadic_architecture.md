# Monadic アーキテクチャドキュメント

## 概要

Monadic Chatのmonadic機能は、AI相互作用全体で会話状態とコンテキストを管理するための構造化された方法を提供します。このリファクタリングされたアーキテクチャは、将来の拡張を可能にしながら100%の後方互換性を維持します。

## クイックスタート

monadic機能は、すべてのMonadicAppインスタンスに自動的に含まれます。既存のアプリに変更は必要ありません - 以前とまったく同じように動作し続けます。

```ruby
# 既存のコードは変更なしで動作
class MyApp < MonadicApp
  def process
    monad = monadic_unit("Hello")          # JSONでラップ
    result = monadic_map(monad) { |ctx|    # コンテキストを変換
      ctx["processed"] = true
      ctx
    }
    monadic_html(result)                    # HTMLとしてレンダリング
  end
end
```

## アーキテクチャ構造

```
lib/monadic/
├── core.rb           # コア関数型プログラミング概念
├── json_handler.rb   # JSONシリアライゼーション/デシリアライゼーション
├── html_renderer.rb  # Web UI用HTMLレンダリング
├── app_extensions.rb # MonadicApp統合レイヤー
└── README.md         # このドキュメント
```

## モジュール階層

```
Monadic::Core
    ↑
Monadic::JsonHandler
    ↑
Monadic::HtmlRenderer
    ↑
Monadic::AppExtensions → MonadicApp
```

## コア概念

### 1. Monadic::Core

純粋な関数型プログラミング操作を提供：

- **`wrap(value, context)`** - monadic構造を作成
- **`unwrap(monad)`** - monadから値を抽出
- **`transform(monad, &block)`** - monadic値にマップ
- **`bind(monad, &block)`** - FlatMap操作
- **`combine(monad1, monad2)`** - 2つのmonadを結合

### 2. Monadic::JsonHandler

JSON固有の操作：

- **`wrap_as_json(message, context)`** - `monadic_unit`と互換
- **`unwrap_from_json(json)`** - `monadic_unwrap`と互換
- **`transform_json(json, &block)`** - `monadic_map`と互換
- **`validate_json_structure(data, expected)`** - 構造検証

### 3. Monadic::HtmlRenderer

HTMLレンダリング機能：

- **`render_as_html(monad, settings)`** - `monadic_html`と互換
- **`json_to_html(hash, settings)`** - コアレンダリングロジック
- 折りたたみ可能なコンテキストセクションを処理
- MathJaxレンダリングをサポート

### 4. Monadic::AppExtensions

次を提供する統合レイヤー：

- 後方互換メソッド
- 強化されたFP操作
- コンテキスト管理
- 検証ユーティリティ

## 使用例

### 基本的な使用方法（後方互換）

```ruby
class MyApp < MonadicApp
  include Monadic::AppExtensions

  def process_message(message)
    # コンテキスト付きでメッセージをラップ
    monad = monadic_unit(message)

    # コンテキストを変換
    result = monadic_map(monad) do |context|
      context["timestamp"] = Time.now
      context["processed"] = true
      context
    end

    # HTMLとしてレンダリング
    monadic_html(result)
  end
end
```

### 高度な使用方法（新機能）

```ruby
# 純粋な関数型スタイル
pure_value = monadic_pure("Hello")

# Bind操作
result = monadic_bind(monad) do |value, context|
  # 新しいmonadを返す
  monadic_unit("Processed: #{value}")
end

# 検証
validation = validate_monadic_structure(monad, {
  "message" => String,
  "context" => Hash
})
```

## 拡張ポイント

### 1. カスタムシリアライゼーション

```ruby
module Monadic
  module XmlHandler
    include Core

    def wrap_as_xml(value, context)
      # カスタムXMLシリアライゼーション
    end
  end
end
```

### 2. プロバイダー固有の処理

```ruby
module Monadic
  class GeminiStrategy
    def format_for_gemini(monad)
      # Gemini固有のフォーマット
    end
  end
end
```

### 3. コンテキスト戦略

```ruby
module Monadic
  module ContextPruning
    def prune_context(context, max_size)
      # プルーニングロジックを実装
    end
  end
end
```

## 実装状況

### 現在の状態
- ✅ モジュールアーキテクチャが実装され、テスト済み
- ✅ すべての6つのmonadicアプリが新しいアーキテクチャで動作
- ✅ パフォーマンス改善が検証済み（Hash操作で50倍高速）
- ✅ 完全な後方互換性を維持
- ✅ monadicコンテキストの空オブジェクトのUI強化

### このアーキテクチャを使用しているMonadicアプリ
1. **Chat Plus** - 推論とコンテキスト追跡
2. **Jupyter Notebook** - 状態管理
3. **Language Practice Plus** - 学習進捗追跡
4. **Novel Writer** - ストーリー状態管理
5. **Translate** - 翻訳コンテキスト
6. **Voice Interpreter** - 音声コンテキスト認識

### UI強化
- 空オブジェクトは空のコンテンツを表示する代わりに「: empty」を表示
- フィールドラベルがフォントウェイトの増加でより目立つように
- 「no value」テキストはイタリック体のグレーでスタイル化
- 読みやすさを向上させるための視覚的階層の改善

## ベストプラクティス

1. **不変性を維持**：monadic値を直接変更しない
2. **型チェックを使用**：外部入力を受け入れる際に構造を検証
3. **エラーを優雅に処理**：JSONパースのフォールバックを常に提供
4. **コンテキスト構造を文書化**：期待されるコンテキストフィールドを明確に定義

## 将来の拡張

### 計画中の機能

1. **Monad トランスフォーマー**：複数のmonadic効果をスタック
2. **エラーMonad**：Either/Result型によるより良いエラーハンドリング
3. **非同期Monad**：非同期操作をmonadicに処理
4. **コンテキストスキーマ**：コンテキスト構造を定義して強制

### 拡張アーキテクチャ

```ruby
# 将来：Monadトランスフォーマー
class StateT < MonadTransformer
  def lift(monad)
    # トランスフォーマーに計算をリフト
  end
end

# 将来：エラーハンドリング
class Result
  def self.success(value)
    # 成功ケース
  end

  def self.failure(error)
    # エラーケース
  end
end
```

## テスト

### ユニットテスト

```ruby
# コア操作をテスト
describe Monadic::Core do
  it "wraps values correctly" do
    monad = wrap("test", { id: 1 })
    expect(monad.value).to eq("test")
    expect(monad.context).to eq({ id: 1 })
  end
end
```

### 統合テスト

```ruby
# 実際のアプリでテスト
describe "Monadic Apps" do
  it "maintains backward compatibility" do
    app = ChatPlusOpenAI.new
    monad = app.monadic_unit("Hello")
    expect(monad).to be_json
  end
end
```

## 貢献

新しいmonadic機能を追加する際：

1. 既存のメソッドを変更せず、モジュールを拡張
2. 後方互換性を維持
3. 新機能のテストを追加
4. ドキュメントを更新
5. プロバイダーの違いを考慮

## 参考文献

- [Functional Programming in Ruby](https://www.rubyguides.com/2018/10/functional-programming-ruby/)
- [Monad Design Pattern](https://en.wikipedia.org/wiki/Monad_(functional_programming))
- [JSON Schema Specification](https://json-schema.org/)
