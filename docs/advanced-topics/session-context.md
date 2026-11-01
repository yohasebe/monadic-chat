# Session Context

Session Context extracts key information from the conversation after each response and shows it in the sidebar. It works in apps with `monadic true`.

> **Note**: `monadic true` also enables [Session State](monadic-mode.md), where the model keeps context by calling tools. The two can be used together.

## Overview

When enabled, Session Context:

1. **Extracts key information**: After each response, an extraction agent reads the turn and extracts information according to the app's schema
2. **Shows it in the sidebar**: The extracted items appear in a panel in the sidebar, by category
3. **Tracks turns**: Each item records the turn in which it was mentioned
4. **Merges variations**: The same name with and without an honorific (for example "田中" and "田中さん") is kept once, in its fuller form

## How It Works

### Architecture

1. The user sends a message and the model responds.
2. The extraction agent sends the turn to the same provider as the conversation, using the provider's default model.
3. The extracted items are sent to the browser, and the sidebar panel is updated.

The default model is `<PROVIDER>_DEFAULT_MODEL` in `~/monadic/config/env`, or the provider default in Monadic Chat. With Ollama, when no default is set, the first installed model is used.

### Default Schema

Without a `context_schema`, Session Context tracks three categories:

| Field | Icon | Description |
|-------|------|-------------|
| **Topics** | `fa-tags` | Main subjects discussed in the conversation |
| **People** | `fa-users` | Names of people mentioned |
| **Notes** | `fa-sticky-note` | Important facts to remember |

## Configuration

### Enabling Session Context

Session Context is on for apps with `monadic true` in their features:

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # Enables Session Context
  end
end
```

### Custom Context Schema

Define the categories to track with the `context_schema` block:

```ruby
app "LanguageTutorOpenAI" do
  features do
    monadic true
  end

  context_schema do
    field :vocabulary, icon: "fa-book", label: "Vocabulary",
          description: "New words and expressions learned"
    field :grammar_points, icon: "fa-list-check", label: "Grammar",
          description: "Grammar concepts covered"
    field :corrections, icon: "fa-pen", label: "Corrections",
          description: "Mistakes and their corrections"
    field :practice_topics, icon: "fa-comments", label: "Practice Topics",
          description: "Conversation topics for practice"
  end
end
```

### Field Options

Each field in `context_schema` accepts the following options:

| Option | Type | Description |
|--------|------|-------------|
| `icon` | String | Font Awesome icon class (e.g., `"fa-tags"`) |
| `label` | String | Name shown in the sidebar panel |
| `description` | String | Tells the extraction agent what to extract |

### Default Icons and Labels

When an option is omitted:

- **Icon**: chosen from the field name when the name is a common one, otherwise a generic circle icon
- **Label**: the field name with `_` replaced by spaces and the first letter capitalized (`:grammar_points` → "Grammar points")
- **Description**: a default description for common field names

## Sidebar Display

### Context Panel

The extracted context appears in a collapsible panel in the sidebar:

- **Section headers**: Each category shows an icon, a label and the number of items
- **Turn labels**: Items are grouped by turn (T1, T2, and so on). Click a turn label to scroll to that message
- **Collapsible sections**: Click a section header to expand or collapse it
- **Toggle all**: A button expands or collapses all sections at once
- **Turn legend**: Shows the number of turns

### Visual Indicators

- An indicator is shown while extraction runs
- Items from the same turn appear together, newer turns first
- A badge shows the number of items in each category
- When you edit a message, its turn is extracted again and marked with an edit badge. When you delete a message, the items of its turn are removed and the later turns are renumbered

## Built-in Apps Using Session Context

| App | Context Fields |
|-----|----------------|
| **Chat Plus** | Topics, People, Notes |
| **Research Assistant** | Topics, Findings, Sources (not in the DeepSeek version) |
| **Math Tutor** | Concepts, Formulas, Tips |
| **Novel Writer** | Characters, Plot, Settings |
| **Voice Interpreter** | Languages, Phrases, Notes |
| **Language Practice Plus** | Vocabulary, Grammar, Tips |
| **Translate** | Languages, Vocabulary, Notes |
| **Jupyter Notebook** | Topics, Code, Notes |
| **Image Generator** | Styles, Prompts, Notes |
| **Video Generator** | Styles, Prompts, Notes |

## Provider Support

Session Context works with every provider: OpenAI, Anthropic (Claude), Google (Gemini), xAI (Grok), Mistral, Cohere, DeepSeek and Ollama. No built-in Ollama app uses `monadic true`; Ollama extraction applies to your own apps.

## Language Support

- Items are extracted in the language of the conversation
- The language can also be detected automatically (`auto`)
- The same name with or without a common Japanese honorific (さん, くん, ちゃん, 様, 氏) is treated as one item

## Privacy Filter

When the Privacy Filter is on, the extraction agent receives the masked text, so the sidebar shows placeholders such as `<<PERSON_1>>` instead of the masked words. If masking fails, or a word you marked would still be in the request to the extraction agent, extraction is skipped for that turn.

## Best Practices

### Designing Custom Schemas

1. **Keep fields focused**: Each field should be a distinct kind of information
2. **Write clear descriptions**: The extraction agent uses them to decide what to extract
3. **Choose meaningful icons**: Icons help users find the categories
4. **Limit the number of fields**: 3 to 6 fields are easy to read

### Schema Design Examples

**For a Code Review App:**
```ruby
context_schema do
  field :files_reviewed, icon: "fa-file-code", label: "Files Reviewed",
        description: "Source code files that were reviewed"
  field :issues_found, icon: "fa-bug", label: "Issues Found",
        description: "Bugs, problems, or code smells identified"
  field :suggestions, icon: "fa-lightbulb", label: "Suggestions",
        description: "Improvement suggestions and recommendations"
end
```

**For a Research Assistant:**
```ruby
context_schema do
  field :topics, icon: "fa-tags", label: "Research Topics",
        description: "Main research subjects and areas explored"
  field :sources, icon: "fa-link", label: "Sources",
        description: "References, papers, and URLs cited"
  field :key_findings, icon: "fa-star", label: "Key Findings",
        description: "Important discoveries and conclusions"
  field :questions, icon: "fa-question", label: "Open Questions",
        description: "Questions that need further investigation"
end
```

## Technical Notes

### Performance

- Extraction runs after each response, without delaying the response
- It usually takes 1 to 3 seconds, depending on the provider

### Data Storage

- The context is stored in the session on the server
- It lasts for the session, and is cleared when you switch apps or start a new conversation
- It is included when you export a conversation, and restored when you import it

### WebSocket Communication

Context updates are sent to the browser as WebSocket messages of type `context_update`:

```json
{
  "type": "context_update",
  "context": {
    "topics": [
      { "text": "Machine Learning", "turn": 1 },
      { "text": "Neural Networks", "turn": 2 }
    ],
    "people": [],
    "notes": [
      { "text": "User prefers Python", "turn": 1 }
    ]
  },
  "schema": {
    "fields": [
      { "name": "topics", "icon": "fa-tags", "label": "Topics", "description": "..." },
      ...
    ]
  },
  "timestamp": 1699500000.123
}
```

## Troubleshooting

### Context Not Appearing

1. **Check `monadic true`**: Make sure the app has it in `features`
2. **Check the API key**: The extraction agent uses the same provider's API
3. **Check Ollama**: With Ollama, make sure Ollama is running and at least one model is installed
4. **Turn on logging**: Set `EXTRA_LOGGING=true` in `~/monadic/config/env` to see the extraction logs

### Empty Fields

- The extraction agent adds only new information from each turn
- Fields with nothing relevant stay empty
- Check that the `description` describes what to extract

### Duplicate Items

- Common variations are merged
- If duplicates appear, make the descriptions more specific

## See Also

- [Session State (Monadic Mode)](monadic-mode.md) - Context kept through tool calls
- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference including `context_schema`
