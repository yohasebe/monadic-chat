# Research Assistant: Provider-Specific Implementations

This document explains why Research Assistant has different implementations across providers and the design decisions behind each variant.

## Overview

Research Assistant is one of the most complex apps in Monadic Chat because it combines:
- Web search capabilities
- Session state management (monadic mode)
- File operations
- Code agent integration (some providers)
- Progress tracking

Not all providers support these features equally, leading to provider-specific implementations.

## Provider Comparison Matrix

| Provider | Web Search | Monadic Mode | Code Agent | File Size |
|----------|------------|--------------|------------|-----------|
| **OpenAI** | Native (Bing) | ✅ Full | GPT-5-Codex | 7.1 KB |
| **Claude** | Tavily | ✅ Full | - | 6.7 KB |
| **Gemini** | Internal Agent | ✅ Full | - | 6.0 KB |
| **Grok** | Native (X/Web) | ✅ Full | Grok-Code | 6.6 KB |
| **Cohere** | Tavily | ✅ Full | - | 6.0 KB |
| **Mistral** | Tavily | ✅ Full | - | 6.2 KB |
| **DeepSeek** | Tavily | ❌ Disabled | - | **1.8 KB** |

## Why DeepSeek is Different

### Problem: Tool Loop Issues

DeepSeek models have a tendency to enter infinite loops when using complex tool sequences:

1. **DSML Format Issues**: DeepSeek outputs tool calls in a proprietary DSML format that can become malformed
2. **Multi-Tool Confusion**: Complex system prompts with multiple tools cause repeated tool invocations
3. **Session State Conflicts**: Monadic mode's state tracking tools trigger additional tool calls

### Solution: Simplified Implementation

```ruby
# research_assistant_deepseek.mdsl
system_prompt <<~TEXT
  You are a professional research assistant who helps users find information.

  ## IMPORTANT: Tool Calling Rules

  1. **Call each tool only ONCE per user message**
  2. **After receiving tool results, provide your final answer immediately**
  3. **DO NOT call the same tool again after receiving its result**
  4. **DO NOT call tools in a loop**
TEXT

features do
  # Note: monadic mode disabled for DeepSeek due to tool loop issues
  monadic false
end
```

**Key Differences**:
- **No monadic mode**: Removes `save_research_progress`, `load_research_progress` tools
- **Explicit anti-loop instructions**: Clear rules to prevent repeated tool calls
- **Simpler system prompt**: Reduced from ~200 lines to ~30 lines
- **Tavily only**: Uses external search API instead of complex agent patterns

## Provider-Specific Web Search Implementations

### Native Search Providers

**OpenAI**:
```ruby
# Uses native Bing integration via websearch_agent
tools do
  import_shared_tools :web_search_tools, visibility: "conditional"
  # websearch_agent is automatically available when websearch: true
end
```

**Grok (xAI)**:
```ruby
# Uses native X/Twitter and web search
features do
  websearch true  # Enables Grok Live Search
end
```

### Tavily Search Providers

**Claude, Cohere, Mistral, DeepSeek**:
```ruby
# External Tavily API for web search
tools do
  import_shared_tools :web_search_tools, visibility: "conditional"
  # tavily_search is used when TAVILY_API_KEY is configured
end
```

### Gemini Special Case

**Problem**: Gemini 3 API has limitations when combining Google Search grounding with other tools.

**Solution**: Internal web search agent that doesn't conflict with file operations:
```ruby
# research_assistant_gemini.mdsl
define_tool "gemini_web_search", "Search the web using Gemini's internal search agent" do
  parameter :query, "string", "Search query", required: true
  visibility "conditional"
end
```

**Note**: This is documented in `docs/basic-usage/basic-apps.md`:
> Gemini Research Assistant uses an internal web search agent (`gemini_web_search`) instead of native Google Search grounding.

## Session State Tools by Provider

### Full Session State (Most Providers)

```ruby
# Available tools for session state management
define_tool "load_research_progress", "Load current research progress"
define_tool "save_research_progress", "Save response and research progress"
define_tool "add_finding", "Add a key finding with source"
define_tool "add_research_topics", "Add research topics explored"
define_tool "add_search", "Log a search performed"
define_tool "add_sources", "Add citations and references"
define_tool "add_research_notes", "Add research observations"
```

### No Session State (DeepSeek)

DeepSeek intentionally excludes all session state tools to prevent tool loops.

## Code Agent Integration

### OpenAI: GPT-5-Codex

```ruby
define_tool "openai_code_agent", "Call GPT-5-Codex for code generation" do
  parameter :task, "string", "Description of the code task", required: true
  parameter :research_context, "string", "Context from research findings", required: false
  visibility "conditional"
  unlock_when tool_request: "openai_code_agent"
end
```

### Grok: Grok-Code

```ruby
define_tool "grok_code_agent", "Call Grok-Code-Fast-1 for code generation" do
  parameter :task, "string", "Description of the code task", required: true
  parameter :research_context, "string", "Context from research findings", required: false
  visibility "conditional"
  unlock_when tool_request: "grok_code_agent"
end
```

### Other Providers

No dedicated code agent - use Coding Assistant app instead.

## Temperature Settings

All Research Assistant variants use `temperature: 0.0` for consistent, factual responses:

```ruby
features do
  temperature 0.0  # Deterministic responses for research accuracy
end
```

## Troubleshooting Provider-Specific Issues

### DeepSeek: Tool Not Executing

**Symptom**: DeepSeek outputs DSML but tools don't execute

**Solutions**:
1. Auto-retry mechanism handles most cases (up to 4 retries)
2. For persistent issues, use `deepseek-reasoner` model
3. Simplify the query to reduce tool complexity

### Gemini: Search Not Working

**Symptom**: Web search returns no results

**Check**:
1. Ensure the internal search agent is being used (not Google grounding)
2. Verify query is not too long or complex
3. Check for API quota limits

### OpenAI/Grok: Native Search Failures

**Symptom**: websearch_agent returns errors

**Check**:
1. Verify API key has search permissions
2. Check for rate limiting
3. Try Tavily fallback if available

## Adding a New Provider

When adding Research Assistant for a new provider, consider:

1. **Web Search Capability**:
   - Native search available? Use it.
   - No native search? Add Tavily integration.

2. **Tool Calling Reliability**:
   - Test complex tool sequences
   - If loops occur, simplify like DeepSeek

3. **Session State Compatibility**:
   - Test monadic mode thoroughly
   - Disable if conflicts with tool calling

4. **System Prompt Length**:
   - Some providers handle long prompts better
   - Adjust complexity based on model capabilities

## Related Documentation

- [DeepSeek Architecture](./vendors/deepseek_architecture.md) - DSML parsing and auto-retry
- [Thinking/Reasoning Display](./thinking_reasoning_display.md) - Reasoning content handling
- [Monadic Architecture](./monadic_architecture.md) - Session state management
- [Web Search Integration](../basic-usage/basic-apps.md#research-assistant) - User documentation
