# Monadicモード（Session State）

MonadicモードはMonadic Chatの特徴的な機能で、AIエージェントとの会話を通じて構造化されたコンテキストを維持・更新できます。これにより、より一貫性のある目的志向の対話が可能になります。

## 概要

Monadicモードでは、アプリは**Session Stateツール**を使用して会話コンテキストを管理します。AIは`save_context`や`load_context`などのツールを呼び出して、会話全体を通じて構造化データを保存・取得します。

### 動作の仕組み

1. **各ターンの開始時**: AIは`load_context`を呼び出して現在の会話状態を取得
2. **処理中**: AIは他のツール（ファイル操作、PDF検索など）を使用
3. **応答前**: AIは`save_context`を呼び出して以下を保存：
   - 応答メッセージ
   - 更新されたコンテキストデータ（トピック、人物、メモなど）

### コンテキスト構造の例

```json
{
  "message": "ユーザーへのAIの応答",
  "reasoning": "応答の背後にある思考プロセス",
  "topics": ["トピック1", "トピック2"],
  "people": ["人物1", "人物2"],
  "notes": ["重要なメモ1", "重要なメモ2"]
}
```

## Session Stateアプリ

以下のアプリがSession State機構を使用してコンテキスト管理を行います：

| アプリ | プロバイダー | 説明 |
|-------|-------------|------|
| Chat Plus | OpenAI, Claude, Ollama | コンテキスト追跡機能付き会話AI |
| Voice Interpreter | OpenAI, Cohere | リアルタイム音声通訳 |
| Language Practice Plus | OpenAI, Claude | フィードバック付き言語学習 |

## アーキテクチャ

Session Stateは以下を通じて実装されています：

1. **MDSLツール定義**: アプリは`define_tool`を使用してコンテキスト管理ツールを定義
2. **ツール実装**: 共有Rubyモジュール（`chat_plus_tools.rb`など）がツールメソッドを実装
3. **セッションストレージ**: コンテキストは`session[:monadic_state]`に保存
4. **TTS統合**: `tts_target`機能がツールパラメータからTTSテキストを抽出

### ツールフローの例

```
ユーザーメッセージ
    ↓
load_context() → 既存の状態を取得
    ↓
リクエストを処理（他のツールを呼び出す場合あり）
    ↓
save_context(message, topics, people, notes) → 状態を保存
    ↓
ユーザーに応答を表示
```

## Session Stateアプリの作成

Session Stateを使用するアプリを作成するには：

```ruby
app "MyAppOpenAI" do
  description "コンテキストを維持するアプリ"
  icon "fa-brain"

  features do
    monadic true  # Session State機構を示す
  end

  system_prompt <<~PROMPT
    あなたはコンテキストを維持するAIアシスタントです。

    ## 必須のツール使用

    1. 各ターンの開始時に必ず`load_context`を呼び出す
    2. 必ず`save_context`で応答とコンテキストを保存する
  PROMPT

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

## UI表現

Webインターフェースでは、Session Stateコンテキストは以下のように表示されます：
- コンテキスト構造を示す折りたたみ可能なセクション
- 空のオブジェクトは「: empty」と明確に表示
- フィールドラベルは太字で表示
- 「monadic」バッジはアプリがSession Stateを使用していることを示す

## TTS統合

音声出力を持つアプリでは、`tts_target`を使用してTTSテキストを含むツールパラメータを指定します：

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_context", "message"
end
```

## ベストプラクティス

1. **最初にload_contextを呼び出す**: 最新の状態を確実に取得
2. **コンテキスト項目を蓄積する**: 明示的に要求されない限り項目を削除しない
3. **一貫した構造を使用**: 会話全体で同じコンテキストフィールドを維持
4. **コンテキストを集中させる**: 後で参照される情報のみを保存

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - 完全なMDSL構文リファレンス
- [基本アプリ](../basic-usage/basic-apps.md) - Session Stateを使用するアプリの例
