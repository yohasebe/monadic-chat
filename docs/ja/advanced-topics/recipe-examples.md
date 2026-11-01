# レシピファイルの例

このページでは、MDSL で書いた Monadic Chat のアプリの、短く完結した例を示します。どれも、そのまま `~/monadic/data/apps/<フォルダ>/` に保存して使えます。もとになる考え方は[常にファサードパターンを使用](./develop_apps.md#always-use-facade-pattern)を、完全なアプリは `docker/services/ruby/apps/` のアプリを参照してください。

## 名前の付け方

アプリの名前は、アプリの名前にプロバイダーを付けたものです（`WordCounterOpenAI`）。アプリのツールの Ruby のメソッドは、アプリの名前からプロバイダーを除いて `Tools` を付けた名前のモジュール（`WordCounterTools`）に置きます。[アプリの開発](./develop_apps.md#file-structure-patterns)を参照してください。

## シンプルなアプリ

システムプロンプトだけのアプリは、MDSL ファイル 1 つで足ります。

```ruby
# tutor_openai.mdsl
app "TutorOpenAI" do
  description "Explains concepts step by step"
  icon "fa-solid fa-chalkboard-user"
  display_name "Tutor"

  llm do
    provider "openai"
    # model omitted: OPENAI_DEFAULT_MODEL, then the provider default
    temperature 0.7
  end

  system_prompt <<~PROMPT
    You are a friendly tutor. Explain concepts clearly, with short examples.
  PROMPT

  features do
    initiate_from_assistant true
  end
end
```

## 独自のツールを持つアプリ

ツールは MDSL ファイルで定義し、そのメソッドはツールのモジュールに書きます。

```ruby
# word_counter_openai.mdsl
app "WordCounterOpenAI" do
  description "Counts the words and characters of a text"
  icon "fa-solid fa-calculator"
  display_name "Word Counter"

  llm do
    provider "openai"
  end

  system_prompt <<~PROMPT
    When the user gives you a text, call count_text and report the result.
  PROMPT

  tools do
    define_tool "count_text", "Count the words and characters of a text" do
      parameter :text, "string", "The text to count", required: true
    end
  end
end
```

```ruby
# word_counter_tools.rb
module WordCounterTools
  def count_text(text:)
    return "❌ The text is empty." if text.to_s.strip.empty?

    "Words: #{text.split.size}, characters: #{text.length}"
  end
end
```

同じアプリをほかのプロバイダーでも使えるようにするには、MDSL ファイルを加えます。たとえば `word_counter_claude.mdsl` に `app "WordCounterClaude"` と `provider "anthropic"` を書きます。ツールのモジュールは同じ `WordCounterTools` が使われます。

## 共有のツールグループを使うアプリ

共有のツールグループで、用意されたツールを使えます。ここでは `:python_execution` が、Python コンテナで Python を実行する `run_code` を加えます。

```ruby
# data_helper_openai.mdsl
app "DataHelperOpenAI" do
  description "Analyzes data with Python"
  icon "fa-solid fa-chart-line"
  display_name "Data Helper"

  llm do
    provider "openai"
  end

  system_prompt <<~PROMPT
    Use run_code to analyze data and draw charts with Python.
    Save charts as files in the current directory. The files are shown in the chat.
  PROMPT

  tools do
    import_shared_tools :python_execution, visibility: "always"
  end
end
```

グループとそのツールは、[ツールグループ](./tool-groups.md)を参照してください。

## セッションコンテキストを使うアプリ

`monadic true` と `context_schema` を書くと、会話の大事な点が取り出され、サイドバーに表示されます。

```ruby
# reading_notes_openai.mdsl
app "ReadingNotesOpenAI" do
  description "Discusses books and keeps notes on them"
  icon "fa-solid fa-book-open"
  display_name "Reading Notes"

  llm do
    provider "openai"
  end

  system_prompt <<~PROMPT
    You discuss books with the user.
  PROMPT

  features do
    monadic true
  end

  context_schema do
    field :books, icon: "fa-book", label: "Books",
          description: "Titles of books mentioned"
    field :themes, icon: "fa-lightbulb", label: "Themes",
          description: "Themes and ideas discussed"
  end
end
```

[セッションコンテキスト](./session-context.md)と [Monadic モード](./monadic-mode.md)を参照してください。

## エージェントのモジュールを使うアプリ

`include_modules` で、Monadic Chat が用意しているモジュールを加えられます。`SecondOpinionAgent` は、別のプロバイダーに回答を確かめてもらう `second_opinion_agent` を加えます。ツールの定義は、メソッドの引数と一致させます。

```ruby
# checked_answers_openai.mdsl
app "CheckedAnswersOpenAI" do
  description "Answers questions and asks another provider to check them on request"
  icon "fa-solid fa-people-arrows"
  display_name "Checked Answers"

  include_modules "SecondOpinionAgent"

  llm do
    provider "openai"
  end

  system_prompt <<~PROMPT
    Answer the user's question. When the user asks for a check,
    call second_opinion_agent with the question and your answer.
  PROMPT

  tools do
    define_tool "second_opinion_agent", "Ask another provider to check an answer" do
      parameter :user_query, "string", "The user's question", required: true
      parameter :agent_response, "string", "Your answer", required: true
      parameter :provider, "string", "Provider to ask (e.g., 'claude', 'gemini')", required: false
    end
  end
end
```

## Monadic Chat が用意しているツール

ツールは、アプリのツールのモジュール、共有のツールグループ（`import_shared_tools`）、`include_modules` で加えたモジュールから来ます。どのツールにも `define_tool` のブロックか、取り込んだグループが要ります。メソッドを書いただけでは、ツールになりません。また、どのアプリにも、共有フォルダのファイルを読み書きする `:file_operations` のグループが加わります。

## ベストプラクティス

1. **ツールのモジュールを使う**：アプリ独自のメソッドは `<アプリ名>Tools` に置きます。
2. **アプリの名前にプロバイダーを含める**：例：`ChatOpenAI`、`CodeInterpreterGemini`
3. **ツールの役割を絞る**：1 つのツールで 1 つのことをします。
4. **エラーを扱う**：入力を確かめ、エラーのメッセージは `❌` で始めます。

## トラブルシューティング

- **アプリがメニューにない**：サーバーの出力で読み込みのエラーを確かめます（`docker logs monadic-chat-ruby-container`）。
- **ツールの実行で "undefined method" になる**：メソッドが `<アプリ名>Tools` モジュールにあるか、そのグループを取り込んでいるかを確かめます。
- **モデルがツールを使わない**：ツールが `tools do` で定義されているか、いつ使うかをシステムプロンプトで伝えているかを確かめます。

## 関連項目

- [アプリの開発](./develop_apps.md) - アプリの開発の詳しいガイド
- [Monadic DSL](./monadic_dsl.md) - MDSL の文法の全体
- [Monadic モード](./monadic-mode.md) - 構造のある文脈について
- [Docker コンテナの追加](./adding-containers.md) - 独自のコンテナで広げる
