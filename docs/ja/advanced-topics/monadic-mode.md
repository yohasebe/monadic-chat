# Monadicモード（Session State）

Monadic モードでは、アプリが話題、メモ、設定などの構造のある文脈を、会話を通して保ち、会話が進むにつれて更新できます。

## 用語ガイド :id=terminology-guide

| 用語 | 説明 |
|------|------|
| **Monadic モード** | アプリで Session State と Session Context をオンにする機能フラグ（`monadic true`） |
| **Session State** | モデルがツールを呼んで読み書きする文脈 |
| **Session Context** | ターンごとに自動で取り出され、サイドバーに表示される大事な情報（[セッションコンテキスト](session-context.md)を参照） |

`monadic true` だけでは、ツールは加わりません。Session State を使うアプリは、共有の `session_context` のツールグループを取り込むか、独自の読み込みと保存のツールを定義します。

## 概要

Session State では、モデルがツールを呼んで、今の文脈を読み、文脈に書き加えます。文脈はセッションの間保たれるので、後のターンで使えます。

### 動作の仕組み

1. モデルが、ツール（たとえば `get_context`）で今の文脈を読みます。
2. 必要に応じてほかのツールも使いながら、利用者に答えます。
3. わかったことを、ツール（たとえば `update_context`）で文脈に書き加えます。

### コンテキスト構造の例

`session_context` のグループは、3 つの一覧を保ちます。

```json
{
  "topics": ["topic1", "topic2"],
  "people": ["person1", "person2"],
  "notes": ["important note 1", "important note 2"]
}
```

## Session Stateアプリ

次の組み込みのアプリが、Session State のツールで文脈を保っています。

| アプリ | ツール |
|--------|--------|
| Chat Plus | `get_context`、`update_context`、`remove_from_context`、`clear_context`（`session_context` のグループ） |
| Research Assistant | `load_research_progress`、`save_research_progress` |
| Math Tutor | `load_learning_progress`、`save_learning_progress` |
| Novel Writer | `load_novel_context`、`save_novel_context` |
| Translate | `load_translation_context`、`save_translation_context`、語彙のツール |
| Voice Interpreter | `load_context`、`save_translation`、`set_target_language` |
| Language Practice Plus | `load_context`、`save_response`、`set_target_language` |
| Jupyter Notebook、Image Generator、Video Generator | `monadic_load_state`（保存はアプリが自分で行います） |

## アーキテクチャ

1. **ツールの定義**：アプリは `session_context` のグループを取り込むか、`define_tool` でツールを定義します。
2. **ツールの実装**：共有のモジュールか、アプリの `*_tools.rb` がツールを実装します。
3. **セッションへの保存**：文脈は、アプリとキーごとに分けてセッションに保存されます（`session[:monadic_state][app][key]`）。版と時刻も記録されます。
4. **読み上げ**：`tts_target` で、読み上げる文をツールのパラメーターから取れます。

### ツールフローの例

1. 利用者がメッセージを送ります。
2. モデルが `get_context` を呼び、今の文脈を受け取ります。
3. モデルが、必要ならほかのツールも呼びながら、求めに応えます。
4. モデルが、新しい話題、人物、事実を `update_context` で書き加えます。
5. 応答が表示され、サイドバーに更新された文脈が表示されます。

## Session Stateアプリの作成

いちばん簡単なのは、`session_context` のグループを取り込むことです。

```ruby
app "MyAppOpenAI" do
  description "An app that keeps context"
  icon "fa-solid fa-brain"

  llm do
    provider "openai"
  end

  features do
    monadic true
  end

  system_prompt <<~PROMPT
    You are an assistant that keeps track of the conversation.
    Call get_context at the start of each turn.
    When the user mentions new topics, people or facts, call update_context.
  PROMPT

  tools do
    import_shared_tools :session_context, visibility: "always"
  end
end
```

ほかのフィールドを使うときは、上の表のアプリと同じように、アプリの `*_tools.rb` に独自の読み込みと保存のツールを書きます。

## UI表現

ツールが保つ文脈は、サイドバーのパネルに表示されます。フィールドはアプリの `context_schema` にしたがいます。[セッションコンテキスト](session-context.md)を参照してください。

## TTS統合

読み上げるアプリでは、`tts_target` で、読み上げる文を持つツールのパラメーターを指定します。

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_translation", "message"
end
```

## ベストプラクティス

1. **最初に文脈を読む**：ターンの初めに、今の文脈を読みます。
2. **文脈に書き加える**：利用者に頼まれない限り、項目を消しません。
3. **同じフィールドを使う**：会話を通して、同じフィールドを使います。
4. **文脈を絞る**：後のターンで使う情報だけを保存します。

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - MDSL の文法の全体
- [セッションコンテキスト](./session-context.md) - サイドバーへの自動の抽出
