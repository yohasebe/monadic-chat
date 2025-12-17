# Session Context

Session Context is an automatic context tracking feature for Monadic apps that enables real-time extraction and display of key information from conversations. This feature works in conjunction with the `monadic: true` setting to provide intelligent context management.

> **Note**: Session Context is one of two context features enabled by `monadic: true`. The other is [Session State](monadic-mode.md) for explicit tool-based context management. These features complement each other.

## Overview

When enabled, Session Context automatically:

1. **Extracts Key Information**: After each AI response, a lightweight extraction agent analyzes the conversation and extracts relevant information based on a configurable schema
2. **Displays in Sidebar**: Extracted context appears in a dedicated panel in the sidebar, organized by category
3. **Tracks Conversation Turns**: Each extracted item includes turn information to show when it was mentioned
4. **Deduplicates Intelligently**: Recognizes similar variations (e.g., "田中" and "田中さん") and keeps only the most complete form

## How It Works

### Architecture

```
User Message → AI Response → Context Extractor Agent → Sidebar Update
                                      ↓
                               Same Provider API
                               (lightweight model)
```

The Context Extractor Agent uses direct HTTP API calls to the same provider as the main conversation, using a cost-efficient model to extract structured information.

### Default Schema

Without custom configuration, Session Context tracks three categories:

| Field | Icon | Description |
|-------|------|-------------|
| **Topics** | 🏷️ | Main subjects discussed in the conversation |
| **People** | 👥 | Names of people mentioned |
| **Notes** | 📝 | Important facts to remember |

## Configuration

### Enabling Session Context

Session Context is enabled automatically for apps with `monadic: true` in their features:

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # Enables Session Context
  end
end
```

### Custom Context Schema

You can define a custom schema to track app-specific information using the `context_schema` block:

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
| `icon` | String | FontAwesome icon class (e.g., `"fa-tags"`) |
| `label` | String | Display name shown in the sidebar panel |
| `description` | String | Description used by the extraction agent to understand what to extract |

### Default Icons and Labels

If not specified, fields use sensible defaults:

- **Icon**: Derived from field name or falls back to a generic circle icon
- **Label**: Field name converted to title case (e.g., `:grammar_points` → "Grammar Points")

## Sidebar Display

### Context Panel

The extracted context appears in a collapsible panel in the sidebar:

- **Section Headers**: Each category shows an icon, label, and item count badge
- **Turn Labels**: Items are grouped by conversation turn (T1, T2, etc.)
- **Collapsible Sections**: Click section headers to expand/collapse
- **Toggle All**: Button to expand or collapse all sections at once
- **Turn Legend**: Shows total number of conversation turns

### Visual Indicators

- Items from the same turn appear together
- Newer items (higher turn numbers) appear first within sections
- A badge shows the total count of items in each category

## Built-in Apps Using Session Context

The following built-in apps use Session Context:

| App | Context Fields |
|-----|----------------|
| **Chat Plus** | Topics, People, Notes (default schema) |
| **Research Assistant** | Topics, People, Notes (default schema) |
| **Math Tutor** | Topics, People, Notes (default schema) |
| **Novel Writer** | Topics, People, Notes (default schema) |
| **Voice Interpreter** | Topics, People, Notes (default schema) |
| **Language Practice Plus** | Target Language, Language Advice, Summary |

## Provider Support

Session Context works with all major AI providers:

- **OpenAI**
- **Anthropic** (Claude)
- **Google** (Gemini)
- **xAI** (Grok)
- **Mistral**
- **Cohere** (Command)
- **DeepSeek**
- **Ollama** (local models)

The extraction uses a lightweight model appropriate for each provider to minimize cost and latency.

## Language Support

Context extraction automatically matches the conversation language:

- Extracts items in the same language as the conversation
- Supports automatic language detection (`auto` mode)
- Handles honorific variations (e.g., Japanese -san, -kun, -sama suffixes)

## Best Practices

### Designing Custom Schemas

1. **Keep fields focused**: Each field should represent a distinct category of information
2. **Write clear descriptions**: The extraction agent uses descriptions to understand what to extract
3. **Choose meaningful icons**: Icons help users quickly identify categories
4. **Limit the number of fields**: 3-6 fields is optimal for usability

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

- Extraction runs asynchronously after each response
- Uses direct HTTP API calls (not WebSocket) to avoid re-triggering message flow
- Typical extraction latency: 1-3 seconds depending on provider

### Data Storage

- Context is stored in the session state on the server
- Context persists for the duration of the session
- Context is cleared when switching apps or starting a new conversation

### WebSocket Communication

Context updates are sent via WebSocket with the message type `context_update`:

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

1. **Check `monadic: true`**: Ensure the feature is enabled in your app
2. **Check API Key**: The extraction agent needs access to the same provider's API
3. **Check Provider**: Some local models (Ollama) may not be available for extraction
4. **Enable Logging**: Set `EXTRA_LOGGING=true` in `~/monadic/config/env` to see extraction logs

### Empty Fields

- The extraction agent only adds new information from each turn
- Fields with no relevant content remain empty
- Check your `description` text to ensure it guides extraction correctly

### Duplicate Items

- The deduplication logic handles common variations
- If duplicates appear, consider making descriptions more specific
- Japanese honorific variations (-san, -kun, etc.) are handled automatically

## See Also

- [Session State (Monadic Mode)](monadic-mode.md) - Explicit tool-based context management
- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference including `context_schema`
- [Basic Apps](../basic-usage/basic-apps.md) - Examples of apps using Session Context
