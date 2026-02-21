# Agent Architecture

## Overview

Monadic Chat uses **agent modules** to encapsulate specialized functionality that the main LLM delegates to. Agents are Ruby modules included in app classes, each providing one or more methods that make direct HTTP calls to AI provider APIs—bypassing the WebSocket/streaming path used for normal chat.

There are two main categories:

| Category | Purpose | Provider Strategy | Inclusion |
|----------|---------|-------------------|-----------|
| **Utility Sub-Agents** | Provider-independent capabilities (vision, STT, video) | Multi-provider with automatic fallback | Included in `MonadicApp` base class |
| **Code Generation Agents** | Dedicated code generation models | Single-provider (provider-specific) | Included only in specific app classes |

Additional agents handle conversation infrastructure (context extraction, second opinion, AI user simulation, command output parsing).

### File Location

All agents live in `lib/monadic/agents/`. They are auto-required via `Dir.glob` in `app.rb`:

```ruby
Dir.glob(File.join(__dir__, "agents", "*.rb")).sort.each { |f| require f }
```

---

## Utility Sub-Agents (Provider-Independent)

These agents enforce the **Provider Independence** principle: when a Claude app calls `analyze_image`, it uses Claude's Vision API—not OpenAI's. Each agent resolves the current provider, checks API key availability, and falls back to an alternative if needed.

### ImageAnalysisAgent

**File**: `agents/image_analysis_agent.rb`
**Included in**: `MonadicApp` (base class)
**Public method**: `image_analysis_agent(message:, image_path:)`

**Supported providers**: OpenAI (`gpt-4o-mini`), Claude (`claude-haiku-4-5-20251001`), Gemini (`gemini-2.0-flash`), Grok (`grok-2-vision-1212`)

**How it works**:
1. Reads image file, validates size (10MB limit), determines MIME type
2. Calls `resolve_vision_provider` — checks current app's provider, falls back to first available vision provider
3. Makes direct HTTP POST to the provider's Vision API
4. Returns text description or error string

**Shared tool group**: `:image_analysis` (registered in `shared_tools/registry.rb`)
**Apps using it**: Content Reader, Speech Draft Helper, and all Code Interpreter / Research Assistant / Coding Assistant variants (16 apps total)

### AudioTranscriptionAgent

**File**: `agents/audio_transcription_agent.rb`
**Included in**: `MonadicApp` (base class)
**Public method**: `audio_transcription_agent(audio_path:, model:, response_format:, lang_code:)`

**Supported providers**: OpenAI (form upload to `/v1/audio/transcriptions`), Gemini (multimodal `generateContent` with `inline_data`)

**How it works**:
1. Resolves audio file path (checks relative, `SHARED_VOL`, `LOCAL_SHARED_VOL`)
2. Validates file exists and size (25MB limit)
3. Calls `resolve_audio_provider` — current provider if supported, else OpenAI → Gemini fallback
4. OpenAI: multipart form upload with model selection
5. Gemini: base64-encoded audio in `inline_data` block
6. Returns transcript text or error string

**Shared tool group**: `:audio_transcription`
**Apps using it**: Content Reader, Speech Draft Helper, Video Describer

### VideoAnalyzeAgent

**File**: `agents/video_analyze_agent.rb`
**Included in**: `MonadicApp` (base class, but typically called from `VideoDescriberApp`)
**Public method**: `analyze_video(file:, fps:, query:, session:)`

**Depends on**: `ImageAnalysisAgent` (for `resolve_vision_provider`, `VISION_MODELS`, `VISION_API_KEYS`), `AudioTranscriptionAgent` (for audio track transcription)

**Supported providers**: OpenAI, Claude, Gemini, Grok (same as ImageAnalysisAgent)

**How it works**:
1. Calls `extract_frames.py` via `send_command` (Python container) — the only remaining `send_command` usage
2. Reads frames JSON directly from shared volume
3. Applies per-provider frame limits (Claude: 20, others: 50) via `balance_frames`
4. Calls provider-specific Vision API with multi-frame payload
5. Transcribes audio track via `audio_transcription_agent`
6. Returns combined description + transcript

**Shared tool group**: `:video_analysis`
**Apps using it**: Video Describer

---

## Code Generation Agents (Single-Provider)

These agents delegate complex coding tasks to dedicated code generation models. Each is provider-specific and only included in apps for that provider.

### OpenAI Code Agent

**File**: `agents/openai_code_agent.rb`
**Module**: `Monadic::Agents::OpenAICodeAgent`
**Public method**: `call_openai_code(prompt:, app_name:, timeout:, model:, &block)`

Uses `/v1/responses` endpoint with adaptive reasoning. Default timeout: 1200s (20 min).

### Grok Code Agent

**File**: `agents/grok_code_agent.rb`
**Module**: `Monadic::Agents::GrokCodeAgent`
**Public method**: `call_grok_code(prompt:, app_name:, timeout:, model:, &block)`

Uses `grok-code-fast-1` via xAI API. Default timeout: 300s (5 min).

### Claude Code Agent

**File**: `agents/claude_code_agent.rb`
**Module**: `Monadic::Agents::ClaudeCodeAgent`
**Public method**: `call_claude_code(prompt:, app_name:, max_tokens:, temperature:, reasoning_effort:, &block)`

Uses Claude Sonnet-4 via Anthropic API.

**Apps using code agents**: Code Interpreter, Coding Assistant, Jupyter Notebook, Research Assistant (one per provider).

---

## Infrastructure Agents

### SecondOpinionAgent

**File**: `agents/second_opinion_agent.rb`
**Public method**: `second_opinion_agent(user_query:, agent_response:, provider:, model:)`

Runs parallel verification across up to 8 providers using Ruby threads. Each thread creates a fresh helper instance to avoid state sharing.

### ContextExtractorAgent

**File**: `agents/context_extractor_agent.rb`
**Public method**: `extract_context(session, user_message, assistant_response, provider, schema, language)`

Extracts structured JSON context from conversations. Uses direct HTTP calls (not `send_query`) to avoid WebSocket loops, since it runs after every assistant response.

### AIUserAgent

**File**: `agents/ai_user_agent.rb`
**Public method**: `process_ai_user(session, params)`

Generates simulated user responses for testing and demo purposes. Multi-provider with app lookup.

### CommandOutputAgent (MonadicAgent)

**File**: `agents/command_output_agent.rb`
**Module**: `MonadicAgent`
**Public method**: `command_output_agent(prompt, content)`

Parses command output into structured JSON. Currently hardcodes `gpt-4.1`.

---

## Design Patterns

### Provider Resolution with Fallback

The utility sub-agents share a common resolution pattern:

```ruby
def resolve_vision_provider
  # 1. Normalize current app's provider name
  current = normalize_provider(settings["provider"])

  # 2. If current provider supports this capability, use it
  return current if VISION_PROVIDERS.include?(current) && api_key_available?(current)

  # 3. Otherwise, find first available provider with an API key
  VISION_PROVIDERS.each do |provider|
    return provider if api_key_available?(provider)
  end

  # 4. Last resort: return default
  VISION_PROVIDERS.first
end
```

**Key principle**: Always prefer the user's chosen provider. Only fall back when the provider lacks the capability (e.g., Cohere has no Vision API) or the API key is missing.

### Direct HTTP Calls

Sub-agents make HTTP calls directly using the `http` gem (or `Net::HTTP` for multipart). They do **not** use `send_query` or the WebSocket streaming path. This avoids:
- Infinite loops (especially for ContextExtractorAgent)
- Unnecessary streaming overhead for one-shot requests
- Coupling to the chat message format

### Retry Strategy

Utility sub-agents use a simple 1-retry pattern with 1-second sleep:

```ruby
retries = 0
begin
  response = HTTP.timeout(...).post(uri, ...)
  # parse response
rescue => e
  retries += 1
  sleep 1 and retry if retries < 1
  "ERROR: #{e.message}"
end
```

Code generation agents use timeout-based error handling without automatic retry.

### Error Message Convention

All agents return error strings starting with `"ERROR:"` on failure. Callers check:

```ruby
if result.to_s.start_with?("ERROR:", "Error:")
  # Handle error
end
```

### Shared Tool Integration

Utility sub-agents expose their functionality to LLMs via shared tool groups:

```
Agent Module                    → Shared Tool Group          → MDSL import
─────────────────────────────────────────────────────────────────────────
ImageAnalysisAgent              → :image_analysis            → import_shared_tools :image_analysis
AudioTranscriptionAgent         → :audio_transcription       → import_shared_tools :audio_transcription
VideoAnalyzeAgent               → :video_analysis            → import_shared_tools :video_analysis
```

Each tool group has an `available?` method that checks API keys, enabling Progressive Tool Disclosure (PTD).

---

## Adding a New Utility Sub-Agent

Follow this checklist when creating a new provider-independent sub-agent:

### 1. Create the agent module

`lib/monadic/agents/my_new_agent.rb`:

```ruby
module MyNewAgent
  # Provider → model mapping (use cheap/fast models for sub-agent tasks)
  MODELS = {
    "openai"    => "gpt-4o-mini",
    "anthropic" => "claude-haiku-4-5-20251001",
    # ... only providers that support this capability
  }.freeze

  API_KEYS = {
    "openai"    => "OPENAI_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY",
  }.freeze

  PROVIDERS = MODELS.keys.freeze

  def my_new_agent(param1:, param2:)
    provider = resolve_my_provider
    api_key = CONFIG[API_KEYS[provider]]&.strip
    return "ERROR: No API key for '#{provider}'" if api_key.nil? || api_key.empty?

    case provider
    when "openai"    then my_call_openai(param1, param2, api_key)
    when "anthropic" then my_call_claude(param1, param2, api_key)
    end
  rescue => e
    "ERROR: #{e.message}"
  end

  private

  def resolve_my_provider
    current = normalize_provider_name(settings["provider"])
    return current if PROVIDERS.include?(current) && !CONFIG[API_KEYS[current]].to_s.strip.empty?
    PROVIDERS.find { |p| !CONFIG[API_KEYS[p]].to_s.strip.empty? } || PROVIDERS.first
  end

  # Provider-specific HTTP calls...
end
```

### 2. Include in MonadicApp (if used across apps)

`lib/monadic/app.rb`:

```ruby
class MonadicApp
  include MonadicAgent
  include MonadicHelper
  include ImageAnalysisAgent
  include AudioTranscriptionAgent
  include MyNewAgent              # Add here
  include StringUtils
```

### 3. Create the shared tool group

`lib/monadic/shared_tools/my_new_tool.rb`:

```ruby
module MonadicSharedTools
  module MyNewTool
    def self.available?
      %w[OPENAI_API_KEY ANTHROPIC_API_KEY].any? { |k| CONFIG && !CONFIG[k].to_s.strip.empty? }
    end

    TOOLS = [{
      type: "function",
      function: {
        name: "my_new_tool",
        description: "Description for the LLM",
        parameters: { ... }
      }
    }].freeze

    def self.tools = TOOLS
  end
end
```

### 4. Register in registry.rb

Add entry to `SHARED_TOOL_GROUPS`:

```ruby
my_new_tool: {
  module_name: 'MonadicSharedTools::MyNewTool',
  tools: [{ name: "my_new_tool", description: "...", parameters: [...] }],
  default_hint: 'Call request_tool("my_new_tool") when you need ...',
  visibility: 'conditional',
  available_when: -> { MonadicSharedTools::MyNewTool.available? }
}
```

### 5. Add require in dsl.rb

```ruby
require_relative 'shared_tools/my_new_tool'
```

### 6. Import in app MSDLs

```ruby
tools do
  import_shared_tools :my_new_tool, visibility: "conditional"
end
```

### 7. Write tests

`spec/unit/agents/my_new_agent_spec.rb` — mock HTTP responses, test provider resolution, error handling, retry logic.

---

## Agent Reference Table

| Agent | Module | Base Class? | Providers | Public Method | Shared Tool Group |
|-------|--------|-------------|-----------|---------------|-------------------|
| ImageAnalysisAgent | Top-level | Yes | 4 (OpenAI, Claude, Gemini, Grok) | `image_analysis_agent` | `:image_analysis` |
| AudioTranscriptionAgent | Top-level | Yes | 2 (OpenAI, Gemini) | `audio_transcription_agent` | `:audio_transcription` |
| VideoAnalyzeAgent | Top-level | Yes | 4 (via ImageAnalysisAgent) | `analyze_video` | `:video_analysis` |
| CommandOutputAgent | Top-level (`MonadicAgent`) | Yes | 1 (OpenAI) | `command_output_agent` | — |
| OpenAICodeAgent | `Monadic::Agents::` | No | 1 (OpenAI) | `call_openai_code` | — |
| GrokCodeAgent | `Monadic::Agents::` | No | 1 (xAI) | `call_grok_code` | — |
| ClaudeCodeAgent | `Monadic::Agents::` | No | 1 (Claude) | `call_claude_code` | — |
| SecondOpinionAgent | Top-level | No | 8 (parallel) | `second_opinion_agent` | — |
| ContextExtractorAgent | Top-level | No | 8 | `extract_context` | — |
| AIUserAgent | Top-level | No | 8 | `process_ai_user` | — |

## Testing

Unit tests for all agents are in `spec/unit/agents/`:

```
spec/unit/agents/
├── ai_user_agent_spec.rb
├── audio_transcription_agent_spec.rb
├── claude_code_agent_spec.rb
├── command_output_agent_spec.rb
├── context_extractor_agent_spec.rb
├── grok_code_agent_spec.rb
├── image_analysis_agent_spec.rb
├── openai_code_agent_spec.rb
├── second_opinion_agent_spec.rb
└── video_analyze_agent_spec.rb
```

Test patterns:
- **Provider resolution**: Mock `settings["provider"]` and `CONFIG` API keys; verify correct provider selected
- **HTTP calls**: Mock HTTP responses per provider; verify request format and response parsing
- **Error handling**: Test missing files, API errors, timeout, missing API keys
- **Retry logic**: Verify retry count and sleep behavior
- **Fallback**: Test that non-vision providers fall back correctly
