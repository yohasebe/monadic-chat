# Session State

Monadic Chat では、返答は 2 つのものを運びます。返答が言ったことと、返答が会話に加えた変化です。変化とは、返答が会話のフォルダに作ったり書き直したりしたファイルと、アプリの Session State です。Session State は、話題、メモ、設定などの作業用のデータで、アプリがツールを呼んで記録します。

## 概要

Session State はターンに属します。返答が変えたものはそのメッセージと一緒に保存され、ある時点の状態は、会話が始まったときの状態に、残っているターンの変化を重ねたものです。

- ターンを削除すると、そのターンが変えたものは元に戻ります。一覧（Translate の用語集、Research Assistant の発見と出典、Novel Writer の登場人物など）は項目ごとに保存するので、ある項目を足したターンを削除すると、その項目だけが元に戻り、ほかの項目は残ります。後のターンが書き直した値は、後の値のまま残ります。
- 履歴から会話を続けたときや、ファイルから読み込んだときも、状態は戻ります。
- 状態を変えられるのは実行中の返答だけで、変えられるのは自分のアプリの状態だけです。

返答が会話のフォルダと状態の外で行ったこと（実行したコードや開いたページなど）は、ターンを削除しても元に戻りません。

Session State に設定は要りません。状態を読むツールと保存するツールを定義したアプリが、Session State を持ちます。

### 動作の仕組み

1. モデルは今の状態を持っています。下の表のうち状態ノートを持つアプリと、`session_context` のツールを使うアプリは、要求のたびに、システムプロンプトの末尾で状態をモデルに渡します。ほかのアプリは、自分で定義したツールで状態を読みます。
2. 必要に応じてほかのツールも使いながら、利用者に答えます。
3. わかったことを、ツール（たとえば `update_context`）で記録します。

## 状態ノート :id=state-notes

アプリは、状態を[作業画面](../basic-usage/web-interface.md#work-screen)のページとして利用者に見せられます。これが状態ノートで、会話のフォルダに `notes/<題名>.md` として置かれます。ページは、状態を変えた返答やファイルを作った返答の後、ターンを削除したとき、履歴から会話を続けたときやファイルから読み込んだときに、状態から作り直されます。それぞれの部分には、最後に変えたターンが付きます。ページの最後には、会話の返答が作ったファイル（グラフや図など）が、作ったターンと一緒に並びます。見せるものが状態になくなると、ページは削除されます。

ページは読むためのものです。モデルはアプリのツールで状態を変え、ページはそれに合わせて変わります。

ページにログを載せるアプリもあります。ログは利用者が読むために足していく文で、モデルは読み返しません。Language Practice Plus の助言や、Voice Interpreter のフレーズがそうです。

## Session Stateアプリ

次の組み込みのアプリが、Session State を保っています。

| アプリ | ツール | 状態ノート |
|--------|--------|------------|
| Chat Plus | `get_context`、`update_context`、`remove_from_context`、`clear_context`（`session_context` のグループ） | Context |
| Research Assistant | `load_research_progress`、`save_research_progress` | Research notes |
| Math Tutor | `load_learning_progress`、`save_learning_progress` | Learning notes |
| Novel Writer | `load_novel_context`、`save_novel_context` | Story notes |
| Translate | `load_translation_context`、`save_translation_context`、語彙のツール | Translation notes |
| Voice Interpreter | `load_context`、`save_translation`、`set_target_language` | Interpreter notes |
| Language Practice Plus | `load_context`、`save_response`、`set_target_language` | Practice notes |
| Jupyter Notebook、Video Generator | `monadic_load_state`（保存はアプリが自分で行います） | — |

## Session Stateアプリの作成

いちばん簡単なのは、`session_context` のグループを取り込む方法です。このグループは 3 つの一覧（話題、人物、メモ）を保ち、**Context** のページとして見せます。

```ruby
app "MyAppOpenAI" do
  description "An app that keeps context"
  icon "fa-solid fa-brain"

  llm do
    provider "openai"
  end

  system_prompt <<~PROMPT
    You are an assistant that keeps track of the conversation.
    When the user mentions new topics, people or facts, call update_context.
  PROMPT

  tools do
    import_shared_tools :session_context, visibility: "always"
  end
end
```

ほかのフィールドを使うときは、アプリの `*_tools.rb` に、`Monadic::SharedTools::MonadicSessionState` の状態のツールを使って、独自の読み込みと保存のツールを書きます。

| ツール | 用途 |
|--------|------|
| `monadic_load_state(key:, default:, session:)` | 値を読む |
| `monadic_save_state(key:, payload:, session:)` | 値を設定する |
| `monadic_put_item(collection:, data:, id:, session:)`、`monadic_remove_item`、`monadic_load_items` | 一覧を項目ごとに保存する |
| `monadic_log(collection:, entries:, session:)` | ログに文を足す |

```ruby
module ReadingNotesTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  def add_book(title:, session: nil)
    monadic_log(collection: "books", entries: [title], session: session)
  end

  def load_books(session: nil)
    monadic_load_items(collection: "books", session: session)
  end

  private

  # The page that shows the state on the work screen.
  def state_notes
    { title: "Reading notes", lists: { "books" => { label: "Books" } } }
  end
end
```

`state_notes` でページを宣言します。`title` がページの題名で、`lists` に一覧にするコレクションを書きます（それぞれに `label`、フィールドのある項目には名前のフィールド `name` と、`fields` にフィールドとラベル）。いくつかのフィールドを持つ 1 つの値を保つアプリでは、その `key` と、`values` に見せるフィールドを書きます。`state_notes` のないアプリは、ページなしで状態を保ちます。

## TTS統合

読み上げるアプリでは、`tts_target` で、読み上げる文を持つツールのパラメーターを指定します。

```ruby
features do
  auto_speech true
  tts_target :tool_param, "save_translation", "message"
end
```

## ベストプラクティス

1. **渡された状態を使う**：状態が要求と一緒に渡されるアプリでは、読み込み直しません。それ以外では、ターンの初めに 1 回読みます。
2. **状態に書き加える**：利用者に頼まれない限り、項目を消しません。
3. **同じフィールドを使う**：会話を通して、同じフィールドを使います。
4. **状態を絞る**：後のターンで使う情報だけを保存します。

## 以前のバージョンの設定

MDSL ファイルの `monadic`、`turn_state`、`context_schema` は、読み込まれますが使われません。削除してかまいません。

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - MDSL の文法の全体
- [ツールグループ](./tool-groups.md) - 共有のツールグループ
