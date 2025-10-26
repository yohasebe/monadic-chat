# Agent Architecture

## Overview

Monadic Chat implements an agent architecture pattern for complex code generation tasks, where a main conversational model delegates specialized tasks to dedicated code generation models.

## Supported Agent Patterns

### GPT-5-Codex Agent (OpenAI)

**Main Model**: GPT-5
**Code Generation Model**: GPT-5-Codex

**Apps Using This Pattern**:
- Code Interpreter OpenAI
- Coding Assistant OpenAI
- Jupyter Notebook OpenAI
- Research Assistant OpenAI

**How It Works**:
1. GPT-5 handles user interaction and tool orchestration
2. When complex code generation is needed, `gpt5_codex_agent` function is called
3. GPT-5-Codex generates optimized code using the `/v1/responses` endpoint with adaptive reasoning
4. Result is returned to GPT-5 for integration into the conversation

### Grok-Code Agent (xAI)

**Main Model**: `grok-4-fast-reasoning` or `grok-4-fast-non-reasoning`
**Code Generation Model**: `grok-code-fast-1`

**Apps Using This Pattern**:
- Code Interpreter Grok
- Coding Assistant Grok
- Jupyter Notebook Grok
- Research Assistant Grok

**How It Works**:
1. `grok-4-fast-reasoning` or `grok-4-fast-non-reasoning` handles user interaction and tool orchestration
2. When complex code generation is needed, `grok_code_agent` function is called
3. `grok-code-fast-1` generates optimized code
4. Result is returned to Grok-4 for integration into the conversation

## Implementation Details

### Module Structure

```ruby
# GPT-5-Codex Agent
module Monadic::Agents::GPT5CodexAgent
  def has_gpt5_codex_access?
    # Checks for OpenAI API key
  end

  def call_gpt5_codex(prompt:, app_name:, timeout:)
    # Calls GPT-5-Codex via responses API
  end

  def build_codex_prompt(task:, context:, current_code:)
    # Builds structured prompt
  end
end

# Grok-Code Agent
module Monadic::Agents::GrokCodeAgent
  def has_grok_code_access?
    # Checks for xAI API key
  end

  def call_grok_code(prompt:, app_name:, timeout:)
    # Calls Grok-Code-Fast-1
  end

  def build_grok_code_prompt(task:, context:, current_code:)
    # Builds structured prompt
  end
end
```

### Tool Definition in MDSL

```ruby
# Example from coding_assistant_openai.mdsl
define_tool "gpt5_codex_agent", "Call GPT-5-Codex agent for complex coding tasks" do
  parameter :task, "string", "Description of the code generation task", required: true
  parameter :context, "string", "Additional context about the project", required: false
  parameter :files, "array", "Array of file objects with path and content", required: false
end

# Example from coding_assistant_grok.mdsl
define_tool "grok_code_agent", "Call Grok-Code-Fast-1 agent for complex coding tasks" do
  parameter :task, "string", "Description of the code generation task", required: true
  parameter :context, "string", "Additional context about the project", required: false
  parameter :files, "array", "Array of file objects with path and content", required: false
end
```

## Access Control

### GPT-5-Codex Access
- All OpenAI API key holders have access to GPT-5-Codex
- No additional model list checking required
- Access determined by presence of `OPENAI_API_KEY`

### Grok-Code Access
- All xAI API key holders have access to Grok-Code-Fast-1
- Access determined by presence of `XAI_API_KEY`

## Fallback Behavior

When agent access is not available:
1. Error message returned with explanation
2. Suggestion to configure appropriate API key
3. Fallback message indicating the app will continue with main model

## Configuration

### Environment Variables
```bash
# OpenAI
OPENAI_API_KEY=sk-...

# xAI
XAI_API_KEY=xai-...
```

### Timeout Configuration
- Default timeout: 120 seconds
- Code Interpreter apps may use longer timeout (360 seconds) for complex algorithms
- Configurable via environment variable: `GPT5_CODEX_TIMEOUT` / `GROK_CODE_TIMEOUT`

## Testing

Unit tests are provided for both agent modules:
- `spec/unit/agents/gpt5_codex_agent_spec.rb`
- `spec/unit/agents/grok_code_agent_spec.rb`

Tests cover:
- Access checking
- Prompt building
- API calls
- Error handling
- Timeout behavior

## Best Practices

1. **Use agents for complex code generation** - Don't call agents for simple snippets
2. **Provide context** - Include relevant context about the project or requirements
3. **Handle timeouts gracefully** - Complex code generation may take time
4. **Cache access checks** - Access status is cached to avoid repeated checks
5. **Log for debugging** - Enable `EXTRA_LOGGING` for detailed agent activity logs