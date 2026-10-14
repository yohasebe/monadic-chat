# Monadic Mode (Session State)

Monadic Mode lets an app keep structured context, such as topics, notes or settings, through the conversation and update it as the conversation goes on.

## Terminology Guide :id=terminology-guide

| Term | Description |
|------|-------------|
| **Monadic Mode** | The feature flag (`monadic true`) that turns on Session State and Session Context for an app |
| **Session State** | Context that the model reads and writes by calling tools |
| **Session Context** | Key information extracted automatically after each turn and shown in the sidebar (see [Session Context](session-context.md)) |

`monadic true` does not add tools by itself. An app that uses Session State imports the shared `session_context` tool group or defines its own load and save tools.

## Overview

With Session State, the model calls tools to read the current context and to add to it. The context is kept for the session, so later turns can use it.

### How It Works

1. The model reads the current context with a tool (for example `get_context`).
2. It answers the user, using other tools as needed.
3. It adds what it learned to the context with a tool (for example `update_context`).

### Context Structure Example

The `session_context` group keeps three lists:

```json
{
  "topics": ["topic1", "topic2"],
  "people": ["person1", "person2"],
  "notes": ["important note 1", "important note 2"]
}
```

## Session State Apps

These built-in apps keep context with Session State tools:

| App | Tools |
|-----|-------|
| Chat Plus | `get_context`, `update_context`, `remove_from_context`, `clear_context` (the `session_context` group) |
| Research Assistant | `load_research_progress`, `save_research_progress` |
| Math Tutor | `load_learning_progress`, `save_learning_progress` |
| Novel Writer | `load_novel_context`, `save_novel_context` |
| Translate | `load_translation_context`, `save_translation_context`, and vocabulary tools |
| Voice Interpreter | `load_context`, `save_translation`, `set_target_language` |
| Language Practice Plus | `load_context`, `save_response`, `set_target_language` |
| Jupyter Notebook, Image Generator, Video Generator | `monadic_load_state` (the app saves the state itself) |

## Architecture

1. **Tool definitions**: The app imports the `session_context` group or defines its tools with `define_tool`.
2. **Tool implementation**: The shared modules or the app's `*_tools.rb` implement the tools.
3. **Session storage**: The context is stored in the session, separately for each app and key (`session[:monadic_state][app][key]`), with a version and a time stamp.
4. **Speech**: The `tts_target` feature can read the text to speak from a tool parameter.

### Tool Flow Example

1. The user sends a message.
2. The model calls `get_context` and receives the current context.
3. The model handles the request, calling other tools if needed.
4. The model calls `update_context` with new topics, people or notes.
5. The response is shown, and the sidebar shows the updated context.

## Creating a Session State App

The simplest way is to import the `session_context` group:

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

For other fields, write your own load and save tools in the app's `*_tools.rb`, as the apps in the table above do.

## UI Representation

The context that the tools keep is shown in the sidebar panel. Its fields follow the app's `context_schema`; see [Session Context](session-context.md).

## TTS Integration

For apps that speak, `tts_target` names the tool parameter that holds the text to speak:

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_translation", "message"
end
```

## Best Practices

1. **Read the context first**: Read the current context at the start of each turn.
2. **Add to the context**: Do not remove items unless the user asks.
3. **Keep the same fields**: Use the same context fields through the conversation.
4. **Keep the context focused**: Store only information that later turns will use.

## See Also

- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference
- [Session Context](./session-context.md) - Automatic extraction to the sidebar
