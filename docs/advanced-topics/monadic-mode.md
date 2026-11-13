# Session State

In Monadic Chat, a reply carries two things: what it says, and what it changed in the chat. The changes are the files the reply made or revised in the chat's folder and the app's Session State: working data, such as topics, notes or settings, that the app records by calling tools.

## Overview

Session State belongs to a turn. What a reply changes is kept with its message, and the state at any moment is what the remaining turns changed, on top of what the chat began with.

- Deleting a turn takes back what it changed. Each entry of a list (Translate's vocabulary, Research Assistant's findings and sources, Novel Writer's characters) is kept apart, so deleting the turn that added an entry takes back that entry and leaves the others. A value that a later turn wrote again keeps the later value.
- The state comes back when the chat is continued from the history or read from a file.
- Only a running reply can change the state, and only the state of its own app.

Things a reply did outside the chat's folder and its state, such as code it ran or a page it opened, are not taken back with the turn.

Session State needs no setting. An app has it when it defines tools that read and save it.

### How It Works

1. The model reads the current state with a tool (for example `get_context`).
2. It answers the user, using other tools as needed.
3. It records what it learned with a tool (for example `update_context`).

## State Notes :id=state-notes

An app can show its state to the user as a page on the [work screen](../basic-usage/web-interface.md#work-screen): its state notes, kept in the chat's folder as `notes/<title>.md`. The page is made from the state after a reply that changed it, when a turn is deleted, and when the chat is continued from the history or read from a file. Each part names the turn that changed it last. When the state holds nothing to show, the page is removed.

The page is for reading. The model changes the state with the app's tools, and the page follows.

Some apps also keep a log on the page: texts that are added for the user to read and that the model does not read back, such as the advice of Language Practice Plus and the phrases of Voice Interpreter.

## Session State Apps

These built-in apps keep Session State:

| App | Tools | State notes |
|-----|-------|-------------|
| Chat Plus | `get_context`, `update_context`, `remove_from_context`, `clear_context` (the `session_context` group) | Context |
| Research Assistant | `load_research_progress`, `save_research_progress` | Research notes |
| Math Tutor | `load_learning_progress`, `save_learning_progress` | Learning notes |
| Novel Writer | `load_novel_context`, `save_novel_context` | Story notes |
| Translate | `load_translation_context`, `save_translation_context`, and vocabulary tools | Translation notes |
| Voice Interpreter | `load_context`, `save_translation`, `set_target_language` | Interpreter notes |
| Language Practice Plus | `load_context`, `save_response`, `set_target_language` | Practice notes |
| Jupyter Notebook, Video Generator | `monadic_load_state` (the app saves the state itself) | — |

## Creating a Session State App

The simplest way is to import the `session_context` group, which keeps three lists (topics, people and notes) and shows them as the **Context** page:

```ruby
app "MyAppOpenAI" do
  description "An app that keeps context"
  icon "fa-solid fa-brain"

  llm do
    provider "openai"
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

For other fields, write your own load and save tools in the app's `*_tools.rb` with the state tools of `Monadic::SharedTools::MonadicSessionState`:

| Tool | Use |
|------|-----|
| `monadic_load_state(key:, default:, session:)` | Read a value |
| `monadic_save_state(key:, payload:, session:)` | Set a value |
| `monadic_put_item(collection:, data:, id:, session:)`, `monadic_remove_item`, `monadic_load_items` | Keep the entries of a list apart |
| `monadic_log(collection:, entries:, session:)` | Add texts to a log |

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

`state_notes` declares the page: its `title`, the collections to list under `lists` (each with a `label`, and for entries with fields a `name` field and `fields` with their labels), and, for an app that keeps one value with several fields, its `key` and the fields to show under `values`. An app without `state_notes` keeps its state without a page.

## TTS Integration

For apps that speak, `tts_target` names the tool parameter that holds the text to speak:

```ruby
features do
  auto_speech true
  tts_target :tool_param, "save_translation", "message"
end
```

## Best Practices

1. **Read the state first**: Read the current state at the start of each turn.
2. **Add to the state**: Do not remove items unless the user asks.
3. **Keep the same fields**: Use the same fields through the conversation.
4. **Keep the state focused**: Store only information that later turns will use.

## Settings of Earlier Versions

`monadic`, `turn_state` and `context_schema` in an MDSL file are read and not used. They can be removed.

## See Also

- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference
- [Tool Groups](./tool-groups.md) - The shared tool groups
