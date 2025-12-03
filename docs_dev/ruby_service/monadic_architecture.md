# Monadic Architecture Documentation (Server-side Concepts)

## Overview

The monadic functionality in Monadic Chat provides a structured way to manage conversation state and context across AI interactions. The current architecture uses **Session State with Tools** for context management.

## Architecture Evolution

### Previous Architecture (Deprecated)

The old architecture used JSON-embedded responses with `monadic_unit` and `monadic_map` functions. This approach required:
- LLM to output structured JSON responses
- Client-side JSON parsing and rendering
- `response_format: json_object` API parameter

**This approach has been deprecated** due to:
- Incompatibility with tool/function calling
- JSON parsing errors and malformed response handling
- Provider-specific quirks requiring extensive workaround code

### Current Architecture: Session State with Tools

The new architecture separates concerns:
- **LLM**: Focuses on natural language responses
- **Tools**: Handle state persistence explicitly
- **Server**: Manages state in `session[:monadic_state]`

## Quick Start

Session State apps define tools for context management:

```ruby
app "ChatPlusOpenAI" do
  features do
    monadic true  # Indicates Session State usage
  end

  tools do
    define_tool "load_context", "Load current conversation context" do
      parameter :session, "object", "Session object", required: false
    end

    define_tool "save_context", "Save response and context" do
      parameter :message, "string", "Your response", required: true
      parameter :topics, "array", "Topics discussed", required: false
      parameter :notes, "array", "Important notes", required: false
    end
  end
end
```

## Architecture Structure

```
lib/monadic/
├── shared_tools/
│   └── monadic_session_state.rb  # Core state management module
├── adapters/vendors/
│   ├── openai_helper.rb          # Provider-specific tool handling
│   ├── claude_helper.rb
│   ├── gemini_helper.rb
│   └── grok_helper.rb
└── dsl.rb                        # MDSL tool definitions
```

## Core Components

### 1. MonadicSessionState Module

Provides shared state management methods:

```ruby
module Monadic::SharedTools::MonadicSessionState
  def monadic_load_state(app: nil, key:, default: nil, session: nil)
    # Returns JSON with success, version, updated_at, data
  end

  def monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)
    # Saves to session[:monadic_state][app_key][key]
    # Returns JSON with success, version, updated_at
  end
end
```

### 2. Tool Flow

```
User Message
    ↓
LLM calls load_context() → Retrieve existing state from session
    ↓
LLM processes request (may call other tools)
    ↓
LLM calls save_context(message, topics, notes) → Persist state
    ↓
Response extracted from tool parameters and displayed
```

### 3. TTS Integration

For voice-enabled apps, the `tts_target` feature extracts speech text from tool parameters:

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_context", "message"
end
```

## Session State Apps

The following apps use Session State mechanism:

| App | Providers | Description |
|-----|-----------|-------------|
| Chat Plus | OpenAI, Claude, Gemini, Grok, Cohere, Mistral, DeepSeek, Ollama | Conversational AI with context tracking |
| Research Assistant | OpenAI, Claude, Gemini, Grok, Cohere, Mistral, DeepSeek | Research progress tracking (topics, findings, sources) |
| Math Tutor | OpenAI, Claude, Gemini, Grok | Learning progress tracking (problems, concepts, weak areas) |
| Voice Interpreter | OpenAI, Cohere | Real-time voice translation |
| Language Practice Plus | OpenAI, Claude | Language learning with feedback |
| Novel Writer | OpenAI | Novel writing progress (plot, characters, chapters) |
| Translate | OpenAI | Translation context management |
| Jupyter Notebook | All providers | Notebook state management |

## State Storage Structure

```ruby
session[:monadic_state] = {
  "ChatPlusOpenAI" => {
    "context" => {
      version: 3,
      updated_at: "2024-11-26T12:00:00Z",
      data: {
        "topics" => ["topic1", "topic2"],
        "people" => ["person1"],
        "notes" => ["important note"]
      }
    }
  }
}
```

## Provider Compatibility

| Provider | Tool Support | Session State |
|----------|-------------|---------------|
| OpenAI | ✅ Full | ✅ Supported |
| Anthropic (Claude) | ✅ Full | ✅ Supported |
| Google (Gemini) | ✅ Full | ✅ Supported |
| xAI (Grok) | ✅ Full | ✅ Supported |
| Cohere | ✅ Full | ✅ Supported |
| Mistral | ✅ Full | ✅ Supported |
| Perplexity | ❌ None | ❌ Not available |
| Ollama | ⚠️ Model-dependent | ⚠️ Model-dependent |
| DeepSeek | ✅ Full | ✅ Supported |

## Best Practices

1. **Always set `monadic true`**: Apps using Session State tools **must** set `monadic true` in the features block
2. **Call load_context first**: Ensure you have the latest state at each turn
3. **Accumulate context items**: Don't remove items unless explicitly asked
4. **Use consistent structure**: Maintain the same context fields throughout
5. **Keep context focused**: Only store information that will be referenced later
6. **Auto-save when appropriate**: Some tools (like Jupyter operations) auto-save state

## The `monadic true` Flag Requirement

**IMPORTANT**: Apps using Session State tools must explicitly set `monadic true` in their features block.

```ruby
features do
  monadic true  # REQUIRED for Session State apps
end
```

### Why is this flag required?

The `monadic true` flag cannot be automatically inferred from tool definitions because:

1. **UI Badge Display**: The frontend shows a visual indicator for monadic apps
2. **Markdown Rendering**: Different rendering logic is applied for monadic vs non-monadic responses
3. **Claude Thinking Mode**: Claude's extended thinking is disabled when `monadic true` + structured outputs
4. **MathJax Escaping**: Different LaTeX escaping rules apply in monadic mode
5. **TTS Processing**: Post-completion TTS behavior differs based on this flag

### Checklist for Session State Apps

When creating an app with Session State:

- [ ] Include `MonadicSessionState` module in the tools class
- [ ] Define `load_*` and `save_*` tools in MDSL
- [ ] Set `monadic true` in features block
- [ ] Add tool usage instructions to system prompt
- [ ] Test that state persists across conversation turns

## Implementation Notes

### Graceful Degradation

Apps can include `MonadicSessionState` but work without it if tools aren't available:

```ruby
class MyApp < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)

  # App works normally even without state management
end
```

### Overhead Considerations

Session State adds overhead compared to simple chat:
- **API calls**: +2 per turn (load + save)
- **Latency**: ~2x increase
- **Cost**: ~1.5-2x token usage

This is why simple Chat apps don't include Session State by default.

## Testing

### Unit Tests

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

## References

- [Monadic Mode (User Documentation)](../../docs/advanced-topics/monadic-mode.md)
- [MDSL Reference](../../docs/advanced-topics/monadic_dsl.md)
- [Tool Groups](../../docs/advanced-topics/tool-groups.md)
