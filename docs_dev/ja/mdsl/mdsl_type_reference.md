# MDSL 型リファレンス

## 概要

このドキュメントは、Monadic DSL（MDSL）パラメータの完全な型リファレンスを提供します。これは、各MDSL設定の期待される型を指定することで[型変換ポリシー](/type_conversion_policy.md)を補完します。

## パラメータ型リファレンス

### Boolean 機能フラグ

すべてのboolean機能フラグは、文字列ではなく実際のboolean値（`true`/`false`）を使用する必要があります。

| パラメータ | 型 | デフォルト | 説明 |
|-----------|------|---------|-------------|
| `auto_speech` | Boolean | `false` | アシスタントメッセージの自動テキスト読み上げを有効化 |
| `easy_submit` | Boolean | `false` | Enterキーでのメッセージ送信を有効化 |
| `initiate_from_assistant` | Boolean | `false` | アシスタントが最初のメッセージを送信することを許可 |
| `mathjax` | Boolean | `false` | 数式表記レンダリングを有効化 |
| `mermaid` | Boolean | `false` | Mermaid図レンダリングを有効化 |
| `abc` | Boolean | `false` | ABC音楽表記レンダリングを有効化 |
| `sourcecode` | Boolean | `false` | 拡張ソースコードハイライトを有効化 |
| `monadic` | Boolean | `false` | JSONコンテキスト付きmonadicモードを有効化 |
| `pdf_vector_storage` | Boolean | `false` | PDFのベクトルストレージを有効化 |
| `websearch` | Boolean | `false` | Web検索機能を有効化 |
| `jupyter` | Boolean | `false` | Jupyterノートブックアクセスを有効化 |
| `image_generation` | Boolean | `false` | AI画像生成を有効化 |
| `video` | Boolean | `false` | 動画アップロードと処理を有効化 |

**例**：
```ruby
app "MyApp" do
  features do
    auto_speech true        # ✅ 正しい：boolean
    easy_submit true        # ✅ 正しい：boolean
  end
end
```

**よくある間違い**：
```ruby
features do
  auto_speech "true"        # ❌ 誤り：文字列
  easy_submit "false"       # ❌ 誤り：文字列（truthyになります！）
end
```

### 文字列パラメータ

| パラメータ | 型 | 必須 | 説明 |
|-----------|------|----------|-------------|
| `app_name` | String | No* | アプリケーション識別子（クラス名から自動導出） |
| `display_name` | String | Yes | UIに表示される表示名 |
| `description` | String or Hash | Yes | アプリの説明（単一文字列または多言語ハッシュ） |
| `icon` | String | Yes | FontAwesomeアイコンまたは絵文字 |
| `initial_prompt` | String | Yes | モデル用のシステムプロンプト |
| `system_prompt` | String | No | `initial_prompt`のエイリアス |
| `group` | String | No | プロバイダーグループ（例："OpenAI", "Anthropic"） |
| `provider` | String | Yes | プロバイダー名（例："openai", "anthropic"） |

*`app_name`は通常、アプリ宣言名から自動導出されます。

**例**：
```ruby
app "ChatOpenAI" do
  display_name "Chat"
  icon "comment"
  description "A conversational AI assistant"

  # または多言語説明
  description do
    en "A conversational AI assistant"
    ja "会話型AIアシスタント"
    zh "对话型AI助手"
  end

  system_prompt <<~PROMPT
    You are a helpful assistant.
  PROMPT

  llm do
    provider "openai"
  end
end
```

### 配列パラメータ

| パラメータ | 型 | 説明 |
|-----------|------|-------------|
| `model` | Array of Strings | アプリで利用可能なモデル選択肢 |

**例**：
```ruby
llm do
  provider "openai"
  model ["gpt-5", "gpt-4.1", "gpt-4.1-mini"]  # ✅ 正しい：文字列の配列
end
```

**よくある間違い**：
```ruby
llm do
  model "gpt-5"  # ❌ 誤り：配列ではなく単一文字列
end
```

### 数値パラメータ

| パラメータ | 型 | 範囲 | 説明 |
|-----------|------|-------|-------------|
| `temperature` | Float | 0.0-2.0 | モデルレスポンスのランダム性 |
| `context_size` | Integer | 1+ | コンテキストとして送信するメッセージ数 |
| `max_tokens` | Integer | 1+ | 生成する最大トークン数 |

**例**：
```ruby
llm do
  temperature 0.7
  max_tokens 2000
  context_size 10
end
```

**注意**：これらは現在、送信中に文字列に変換されますが、JavaScriptは型強制を通じてこれを適切に処理します。数値比較が問題になった場合、将来的に明示的な型保持が追加される可能性があります。

### Enumパラメータ

| パラメータ | 型 | 有効な値 | 説明 |
|-----------|------|--------------|-------------|
| `reasoning_effort` | String | "minimal", "low", "medium", "high" | OpenAI推論努力レベル |

**プロバイダー固有**：
- **OpenAI**："minimal", "low", "medium", "high"
- **Anthropic**：思考予算による予算値（整数）
- **Google**：思考設定による設定オブジェクト

**例**：
```ruby
llm do
  provider "openai"
  model ["gpt-5"]
  reasoning_effort "medium"  # ✅ 正しい：文字列enum値
end
```

### 複雑なパラメータ

#### tools

**型**：Hash（JSONに変換）

**説明**：関数呼び出しのツール定義

**例**：
```ruby
tools do
  define_tool "search_web", "Search the web for information" do
    parameter :query, "string", "Search query", required: true
    parameter :limit, "integer", "Maximum results", required: false
  end

  define_tool "calculate", "Perform calculations" do
    parameter :expression, "string", "Mathematical expression", required: true
  end
end
```

**内部表現**：
```ruby
# ハッシュ構造に変換
{
  "search_web" => {
    name: "search_web",
    description: "Search the web for information",
    parameters: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Maximum results" }
    },
    required: ["query"]
  },
  # ...
}
```

#### context_management

**型**：Hash

**説明**：Monadicコンテキスト管理設定

**例**：
```ruby
context_management do
  edits [
    {
      role: "user",
      content: "Update context based on conversation"
    }
  ]
end
```

### 特別なパラメータ

#### disabled

**型**：Boolean式の結果をStringとして

**説明**：条件に基づいてアプリの可用性を制御

**例**：
```ruby
features do
  disabled !CONFIG["OPENAI_API_KEY"]  # "true"または"false"文字列として評価
end
```

**なぜString**：
- Rubyでboolean式として評価
- 表示目的でフロントエンドに文字列として送信
- フロントエンドはtruthyをチェック

## 型検証

### ランタイム検証

MDSLローダーには基本的な検証が含まれています：

```ruby
# lib/monadic/dsl.rb
def validate!
  raise ValidationError, "Name is required" unless @name
  raise ValidationError, "Settings are required" if @settings.empty?
  raise ValidationError, "Provider is required" unless @settings[:provider]
  true
end
```

### 新しいパラメータの追加

新しいMDSLパラメータを追加する際：

1. **型カテゴリを決定**：
   - Boolean機能フラグ？ → `websocket.rb`の型保持リストに追加
   - Array/Object？ → 明示的な`.to_json`ハンドリングを追加
   - Numeric？ → 型保持の必要性を検討
   - String？ → デフォルトハンドリングで問題なし

2. **DSLパーサーを更新**（必要な場合）：
   - 適切なコンテキストクラスにメソッドを追加
   - 機能フラグの場合は`FEATURE_MAP`に追加

3. **ドキュメントを更新**：
   - この型リファレンスに追加
   - 使用例で`monadic_dsl.md`を更新
   - ハンドリング詳細で`type_conversion_policy.md`を更新

4. **テストを追加**：
   - DSLパース用のユニットテスト
   - アプリ切り替え用の統合テスト
   - 型一貫性テスト

### 例：新しいBoolean機能の追加

```ruby
# 1. MDSLで定義
app "MyApp" do
  features do
    my_new_feature true  # 新しいbooleanフラグ
  end
end

# 2. 型保持リストに追加（websocket.rb）
elsif ["auto_speech", ..., "my_new_feature"].include?(p.to_s)
  apps[k][p] = m

# 3. toBoolを使用してJavaScriptで使用
if (toBool(apps[appValue]["my_new_feature"])) {
  // 機能を有効化
}

# 4. テストを追加
it "preserves my_new_feature boolean value" do
  # アプリ切り替えが正しいbooleanを保持することをテスト
end
```

## 型強制ルール

### Ruby → JSON

| Ruby型 | JSON型 | 注記 |
|-----------|-----------|-------|
| `true`/`false` | Boolean | 機能フラグ用に保持 |
| `Array` | Array | `.to_json`経由でJSONシリアライズ |
| `Hash` | Object | `.to_json`経由でJSONシリアライズ |
| `String` | String | 直接変換 |
| `Integer` | Number* | 現在は文字列化されるが、パース可能 |
| `Float` | Number* | 現在は文字列化されるが、パース可能 |
| `nil` | null | JSON nullに変換 |

*数値型は現在、送信中に文字列に変換されます。

### JSON → JavaScript

| JSON型 | JavaScript型 | 使用方法 |
|-----------|-----------------|-------|
| Boolean | Boolean | 直接評価：`if (value)`|
| String | String | "true"/"false"には`toBool()`が必要 |
| Array | Array | 文字列化されている場合は`JSON.parse()`が必要 |
| Object | Object | 文字列化されている場合は`JSON.parse()`が必要 |
| Number | Number | 文字列からの自動強制が機能 |
| null | null | Falsy値 |

## よくある型の落とし穴

### 1. 文字列Boolean評価

```javascript
// ❌ 問題
"false" → truthy（trueと評価）
"true"  → truthy（trueと評価）

// ✅ 解決策
toBool("false") → false
toBool("true")  → true
```

### 2. 文字列としての配列

```javascript
// ❌ 問題
typeof apps[appValue]["models"] === "string"  // "[\"gpt-5\",\"gpt-4.1\"]"

// ✅ 解決策
const models = JSON.parse(apps[appValue]["models"]);
```

### 3. 数値文字列比較

```javascript
// ⚠️ 注意
"10" > "2"  // false（文字列比較）
10 > 2      // true（数値比較）

// ✅ 安全
parseInt("10", 10) > parseInt("2", 10)  // true
```

### 4. Null vs Undefined vs False

```javascript
// すべてfalsy、しかし異なる
if (null) { }        // 実行されない
if (undefined) { }   // 実行されない
if (false) { }       // 実行されない

// しかし厳密等価では異なる
null === undefined        // false
null === false           // false
undefined === false      // false

// 一貫したハンドリングにはtoBoolを使用
toBool(null)      → false
toBool(undefined) → false
toBool(false)     → false
```

## ベストプラクティス

### 1. 常にMDSLで正しい型を使用

```ruby
# ✅ 良い
features do
  auto_speech true

  easy_submit true
end

# ❌ 悪い
features do
  auto_speech "true"
  image "false"
  easy_submit 1  # 動作するが一貫性がない
end
```

### 2. 機能フラグにはtoBoolを使用

```javascript
// ✅ 常に機能フラグにはtoBoolを使用
if (toBool(params["auto_speech"])) {
  enableTTS();
}

// ❌ 直接評価を信頼しない
if (params["auto_speech"]) {  // 文字列"false"の可能性！
  enableTTS();
}
```

### 3. JSON配列/オブジェクトをパース

```javascript
// ✅ 必要な時にパース
const models = JSON.parse(apps[appValue]["models"]);
const tools = JSON.parse(apps[appValue]["tools"]);

// ❌ 文字列化されたバージョンを直接使用しない
if (apps[appValue]["models"].includes("gpt-5")) {  // 誤り！
}
```

### 4. 数値の明示的な型変換

```javascript
// ✅ 明示的変換
const temp = parseFloat(params["temperature"]);
const size = parseInt(params["context_size"], 10);

// ⚠️ 暗黙的変換（通常は機能するが、注意）
if ($("#temperature").val() > 0.5) {  // 自動強制
}
```

## 関連ドキュメント

- [型変換ポリシー](../type_conversion_policy.md) - 全体的なポリシードキュメント
- [Monadic DSLドキュメント](../../../../docs/ja/advanced-topics/monadic_dsl.md) - ユーザー向けDSLガイド
- [よくある問題](../common-issues.md) - トラブルシューティングガイド

## 改訂履歴

- 2025-01：初期型リファレンスドキュメント
- 包括的なboolean機能フラグ型を追加
- 型強制ルールを文書化
- よくある落とし穴とベストプラクティスを追加
