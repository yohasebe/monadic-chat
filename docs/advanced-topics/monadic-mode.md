# Monadic Mode (Session State)

Monadic Mode is a distinctive feature of Monadic Chat that allows you to maintain and update structured context throughout your conversation with AI agents. This enables more coherent and purposeful interactions.

## Overview

In Monadic Mode, apps use **Session State tools** to manage conversation context. The AI calls tools like `save_context` and `load_context` to persist and retrieve structured data throughout the conversation.

### How It Works

1. **At the start of each turn**: The AI calls `load_context` to retrieve the current conversation state
2. **During processing**: The AI may use additional tools (file operations, PDF search, etc.)
3. **Before responding**: The AI calls `save_context` with:
   - The response message
   - Updated context data (topics, people, notes, etc.)

### Context Structure Example

```json
{
  "message": "The AI's response to the user",
  "reasoning": "The thought process behind the response",
  "topics": ["topic1", "topic2"],
  "people": ["person1", "person2"],
  "notes": ["important note 1", "important note 2"]
}
```

## Session State Apps

The following apps use Session State mechanism for context management:

| App | Provider | Description |
|-----|----------|-------------|
| Chat Plus | OpenAI, Claude, Ollama | Conversational AI with context tracking |
| Voice Interpreter | OpenAI, Cohere | Real-time voice translation |
| Language Practice Plus | OpenAI, Claude | Language learning with feedback |

## Architecture

Session State is implemented through:

1. **MDSL Tool Definitions**: Apps define context management tools using `define_tool`
2. **Tool Implementation**: Shared Ruby modules (`chat_plus_tools.rb`, etc.) implement the tool methods
3. **Session Storage**: Context is stored in `session[:monadic_state]`
4. **TTS Integration**: The `tts_target` feature extracts TTS text from tool parameters

### Tool Flow Example

```
User Message
    ↓
load_context() → Retrieve existing state
    ↓
Process request (may call other tools)
    ↓
save_context(message, topics, people, notes) → Persist state
    ↓
Response displayed to user
```

## Creating a Session State App

To create an app that uses Session State:

```ruby
app "MyAppOpenAI" do
  description "An app that maintains context"
  icon "fa-brain"

  features do
    monadic true  # Indicates Session State mechanism
  end

  system_prompt <<~PROMPT
    You are an AI assistant that maintains context.

    ## MANDATORY TOOL USAGE

    1. ALWAYS call `load_context` at the start of each turn
    2. ALWAYS call `save_context` with your response and context
  PROMPT

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

## UI Representation

In the web interface, Session State context appears as:
- Collapsible sections showing the context structure
- Empty objects display as ": empty" for clarity
- Field labels are shown with increased font weight
- The "monadic" badge indicates an app uses Session State

## TTS Integration

For apps with voice output, use `tts_target` to specify which tool parameter contains the TTS text:

```ruby
features do
  monadic true
  auto_speech true
  tts_target :tool_param, "save_context", "message"
end
```

## Best Practices

1. **Always call load_context first**: This ensures you have the latest state
2. **Accumulate context items**: Don't remove items unless explicitly asked
3. **Use consistent structure**: Maintain the same context fields throughout
4. **Keep context focused**: Only store information that will be referenced later

## See Also

- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference
- [Basic Apps](../basic-usage/basic-apps.md) - Examples of apps using Session State
