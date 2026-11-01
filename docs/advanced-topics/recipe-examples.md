# Recipe File Examples

This page shows short, complete examples of Monadic Chat apps in MDSL. Each one can be saved in `~/monadic/data/apps/<folder>/` as it is. For the patterns behind them, see [Always Use Facade Pattern](./develop_apps.md#always-use-facade-pattern); for complete apps, see the apps in `docker/services/ruby/apps/`.

## Naming

The app name is the app's name plus the provider (`WordCounterOpenAI`). Ruby methods for the app's tools go in a module named after the app without the provider, plus `Tools` (`WordCounterTools`). See [Developing Apps](./develop_apps.md#file-structure-patterns).

## A Simple App

An app with only a system prompt needs a single MDSL file.

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

## An App with Its Own Tools

The tool is defined in the MDSL file, and its method is in the tools module.

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

To offer the same app with another provider, add another MDSL file, such as `word_counter_claude.mdsl` with `app "WordCounterClaude"` and `provider "anthropic"`. The same `WordCounterTools` module is used.

## An App with Shared Tool Groups

Shared tool groups bring ready-made tools. Here `:python_execution` provides `run_code`, which runs Python in the Python container.

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

For the groups and their tools, see [Tool Groups](./tool-groups.md).

## An App with Session Context

With `monadic true` and a `context_schema`, the important points of the conversation are extracted and shown in the sidebar.

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

See [Session Context](./session-context.md) and [Monadic Mode](./monadic-mode.md).

## An App Using an Agent Module

`include_modules` adds a module that Monadic Chat provides. `SecondOpinionAgent` provides `second_opinion_agent`, which asks another provider to check an answer. The tool definition must match the method's arguments.

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

## Tools Provided by Monadic Chat

Tools come from the app's tools module, from shared tool groups (`import_shared_tools`), or from modules added with `include_modules`. Each one needs a `define_tool` block or an imported group; defining a method alone does not make it a tool. Every app also gets the `:file_operations` group for reading and writing files in the shared folder.

## Best Practices

1. **Use the tools module**: Put the app's own methods in `<AppName>Tools`.
2. **Include the provider in the app name**: e.g., `ChatOpenAI`, `CodeInterpreterGemini`.
3. **Keep tools focused**: Each tool should do one thing.
4. **Handle errors**: Check the inputs, and start error messages with `❌`.

## Troubleshooting

- **The app is not in the menu**: Check the server output for loading errors (`docker logs monadic-chat-ruby-container`).
- **"undefined method" when a tool runs**: Check that the method is in the `<AppName>Tools` module, or that its group is imported.
- **The model does not use a tool**: Check that the tool is defined in `tools do` and that the system prompt says when to use it.

## See Also

- [Developing Apps](./develop_apps.md) - Detailed guide for app development
- [Monadic DSL](./monadic_dsl.md) - Complete MDSL syntax reference
- [Monadic Mode](./monadic-mode.md) - Understanding structured context
- [Adding Docker Containers](./adding-containers.md) - Extending with custom containers
