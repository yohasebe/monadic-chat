# Monadic アーキテクチャドキュメント（サーバーサイド概念）

## 概要

Monadic Chatのmonadic機能は、AI対話全体で会話状態とコンテキストを管理するための構造化された方法を提供します。現在のアーキテクチャは、コンテキスト管理に**Session State + Tools**を使用しています。

## アーキテクチャの進化

### 旧アーキテクチャ（非推奨）

旧アーキテクチャは`monadic_unit`と`monadic_map`関数を使用したJSON埋め込みレスポンスを使用していました。このアプローチには以下が必要でした：
- LLMが構造化JSONレスポンスを出力
- クライアントサイドでのJSONパースとレンダリング
- `response_format: json_object` APIパラメータ

**このアプローチは非推奨となりました**。理由：
- ツール/ファンクション呼び出しとの非互換性
- JSONパースエラーと不正なレスポンスの処理
- プロバイダー固有の問題に対する大量の回避コード

### 現在のアーキテクチャ：Session State + Tools

新しいアーキテクチャは関心を分離します：
- **LLM**：自然言語応答に集中
- **ツール**：状態の永続化を明示的に処理
- **サーバー**：`session[:monadic_state]`で状態を管理

## クイックスタート

Session Stateアプリはコンテキスト管理用のツールを定義します：

```ruby
app "ChatPlusOpenAI" do
  features do
    monadic true  # Session State使用を示す
  end

  tools do
    define_tool "load_context", "現在の会話コンテキストを読み込む" do
      parameter :session, "object", "セッションオブジェクト", required: false
    end

    define_tool "save_context", "応答とコンテキストを保存する" do
      parameter :message, "string", "あなたの応答", required: true
      parameter :topics, "array", "議論されたトピック", required: false
      parameter :notes, "array", "重要なメモ", required: false
    end
  end
end
```

## アーキテクチャ構造

```
lib/monadic/
├── shared_tools/
│   └── monadic_session_state.rb  # コア状態管理モジュール
├── adapters/vendors/
│   ├── openai_helper.rb          # プロバイダー固有のツール処理
│   ├── claude_helper.rb
│   ├── gemini_helper.rb
│   └── grok_helper.rb
└── dsl.rb                        # MDSLツール定義
```

## コアコンポーネント

### 1. MonadicSessionStateモジュール

共有状態管理メソッドを提供：

```ruby
module Monadic::SharedTools::MonadicSessionState
  def monadic_load_state(app: nil, key:, default: nil, session: nil)
    # success、version、updated_at、dataを含むJSONを返す
  end

  def monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)
    # session[:monadic_state][app_key][key]に保存
    # success、version、updated_atを含むJSONを返す
  end
end
```

### 2. ツールフロー

```
ユーザーメッセージ
    ↓
LLMがload_context()を呼び出し → セッションから既存状態を取得
    ↓
LLMがリクエストを処理（他のツールを呼び出す場合あり）
    ↓
LLMがsave_context(message, topics, notes)を呼び出し → 状態を永続化
    ↓
ツールパラメータから応答を抽出して表示
```

### 3. TTS統合

音声対応アプリでは、`tts_target`機能がツールパラメータから読み上げテキストを抽出：

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_context", "message"
end
```

## Session Stateアプリ

以下のアプリがSession State機構を使用：

| アプリ | プロバイダー | 説明 |
|-------|-------------|------|
| Chat Plus | OpenAI, Claude, Gemini, Grok, Cohere, Mistral, DeepSeek, Ollama | コンテキスト追跡付き会話AI |
| Research Assistant | OpenAI, Claude, Gemini, Grok, Cohere, Mistral, DeepSeek | 研究進捗追跡（トピック、発見、ソース） |
| Math Tutor | OpenAI, Claude, Gemini, Grok | 学習進捗追跡（問題、概念、弱点） |
| Voice Interpreter | OpenAI, Cohere | リアルタイム音声通訳 |
| Language Practice Plus | OpenAI, Claude | フィードバック付き言語学習 |
| Novel Writer | OpenAI | 小説執筆進捗（プロット、キャラクター、章） |
| Translate | OpenAI | 翻訳コンテキスト管理 |
| Jupyter Notebook | 全プロバイダー | ノートブック状態管理 |

## 状態ストレージ構造

```ruby
session[:monadic_state] = {
  "ChatPlusOpenAI" => {
    "context" => {
      version: 3,
      updated_at: "2024-11-26T12:00:00Z",
      data: {
        "topics" => ["トピック1", "トピック2"],
        "people" => ["人物1"],
        "notes" => ["重要なメモ"]
      }
    }
  }
}
```

## プロバイダー互換性

| プロバイダー | ツールサポート | Session State |
|-------------|---------------|---------------|
| OpenAI | ✅ 完全 | ✅ 対応 |
| Anthropic (Claude) | ✅ 完全 | ✅ 対応 |
| Google (Gemini) | ✅ 完全 | ✅ 対応 |
| xAI (Grok) | ✅ 完全 | ✅ 対応 |
| Cohere | ✅ 完全 | ✅ 対応 |
| Mistral | ✅ 完全 | ✅ 対応 |
| Perplexity | ❌ なし | ❌ 利用不可 |
| Ollama | ⚠️ モデル依存 | ⚠️ モデル依存 |
| DeepSeek | ✅ 完全 | ✅ 対応 |

## ベストプラクティス

1. **`monadic true`を必ず設定**：Session Stateツールを使用するアプリは、featuresブロックで`monadic true`を**必ず**設定する
2. **最初にload_contextを呼び出す**：各ターンで最新の状態を確保
3. **コンテキスト項目を蓄積**：明示的に要求されない限り項目を削除しない
4. **一貫した構造を使用**：会話全体で同じコンテキストフィールドを維持
5. **コンテキストを集中させる**：後で参照される情報のみを保存
6. **適切な場合は自動保存**：一部のツール（Jupyter操作など）は状態を自動保存

## `monadic true`フラグの必須性

**重要**：Session Stateツールを使用するアプリは、featuresブロックで明示的に`monadic true`を設定する必要があります。

```ruby
features do
  monadic true  # Session Stateアプリでは必須
end
```

### なぜこのフラグが必要か？

`monadic true`フラグはツール定義から自動推論できません。理由：

1. **UIバッジ表示**：フロントエンドがmonadicアプリ用のビジュアルインジケーターを表示
2. **Markdownレンダリング**：monadic/非monadicレスポンスで異なるレンダリングロジックを適用
3. **Claude Thinkingモード**：`monadic true` + structured outputsの場合、thinkingを無効化
4. **MathJaxエスケープ**：monadicモードでは異なるLaTeXエスケープルールを適用
5. **TTS処理**：post-completion TTSの動作がこのフラグに基づいて異なる

### Session Stateアプリ作成チェックリスト

Session Stateを使用するアプリを作成する際：

- [ ] ツールクラスに`MonadicSessionState`モジュールをインクルード
- [ ] MDSLで`load_*`と`save_*`ツールを定義
- [ ] featuresブロックで`monadic true`を設定
- [ ] システムプロンプトにツール使用手順を追加
- [ ] 会話ターン間で状態が永続化されることをテスト

## 実装ノート

### グレースフルデグラデーション

アプリは`MonadicSessionState`をインクルードしても、ツールが利用できない場合は動作可能：

```ruby
class MyApp < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)

  # 状態管理なしでもアプリは正常に動作
end
```

### オーバーヘッドの考慮

Session Stateはシンプルなチャットと比較してオーバーヘッドを追加：
- **API呼び出し**：ターンごとに+2回（load + save）
- **レイテンシ**：約2倍増加
- **コスト**：約1.5-2倍のトークン使用量

これが、シンプルなChatアプリがデフォルトでSession Stateを含まない理由です。

## テスト

### ユニットテスト

```ruby
describe Monadic::SharedTools::MonadicSessionState do
  it "saves and loads state correctly" do
    session = { monadic_state: {} }

    app.monadic_save_state(
      app: "TestApp",
      key: "context",
      payload: { "topics" => ["test"] },
      session: session
    )

    result = app.monadic_load_state(
      app: "TestApp",
      key: "context",
      session: session
    )

    expect(JSON.parse(result)["data"]["topics"]).to eq(["test"])
  end
end
```

## 参考文献

- [Monadicモード（ユーザードキュメント）](../../docs/ja/advanced-topics/monadic-mode.md)
- [MDSLリファレンス](../../docs/ja/advanced-topics/monadic_dsl.md)
- [ツールグループ](../../docs/ja/advanced-topics/tool-groups.md)
