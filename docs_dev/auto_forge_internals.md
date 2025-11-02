# AutoForge Internal Documentation

## Overview

AutoForge (public name: "Artifact Builder") is a sophisticated multi-layer application generation system that combines GPT-5, Claude Code, or Grok-4-Fast-Reasoning orchestration with provider-specific code generation (OpenAI Code, Claude Code, or Grok-Code-Fast-1).

## Architecture

### Layer Architecture

```
┌──────────────────────────────────────────────┐
│              MDSL Framework                  │
│  (auto_forge_openai/claude/grok.mdsl)        │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│         Orchestration Layer                  │
│  (GPT-5 / Claude Code / Grok-4-Fast-         │
│   Reasoning via provider APIs)               │
│   - User interaction                         │
│   - Planning & coordination                  │
│   - Tool invocation                          │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│         Tool Methods Layer                   │
│         (auto_forge_tools.rb)                │
│   - generate_application                     │
│   - debug_application                        │
│   - list_projects                            │
│   - validate_specification                   │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│        Code Generation Layer                 │
│  (OpenAI Code / Claude Code /                │
│   Grok-Code-Fast-1 via provider agents)      │
│   - HTML/CSS/JS/CLI generation               │
│   - via provider-specific agents             │
└──────────────────────────────────────────────┘
```

### Key Components

#### 1. MDSL Configuration (`auto_forge_openai.mdsl`, `auto_forge_claude.mdsl`, `auto_forge_grok.mdsl`)
- Defines the app interface and system prompt for each provider
- Configures available models:
  - OpenAI: gpt-5 for orchestration; gpt-5-codex and gpt-4.1 as fallbacks for code generation
  - Claude: claude-sonnet-4-5-20250929 for both orchestration and code generation
  - Grok: grok-4-fast-reasoning and grok-4-fast-non-reasoning for orchestration; grok-code-fast-1 for code generation
- Registers tool methods, including `generate_additional_file`
- Uses the provider's chat/responses API for orchestration

#### 2. Tool Methods (`auto_forge_tools.rb`)
- Implements the core logic for each tool
- Includes provider-specific agents:
  - `OpenAICodeAgent` for OpenAI code generation
  - `ClaudeCodeAgent` for Claude code generation
  - `GrokCodeAgent` for Grok code generation
- Handles project management, optional CLI asset generation, and file I/O
- Coordinates between orchestration and code generation

#### 3. Application Logic (`auto_forge.rb`)
- Main application class
- Manages project lifecycle
- Handles file operations
- Context persistence for modifications

#### 4. HTML Generators
- **OpenAI**: `agents/html_generator.rb` with OpenAICodeAgent - Interfaces with OpenAI Code
- **Claude**: Uses `agents/html_generator.rb` with ClaudeCodeAgent callback - Interfaces with Claude models via claude_code_agent
- **Grok**: `agents/grok_html_generator.rb` with GrokCodeAgent - Interfaces with Grok-Code-Fast-1
- Builds prompts optimized for each provider's code generation model
- Handles both new generation and modifications
- Extracts and validates HTML output

#### 5. Utilities (`auto_forge_utils.rb`)
- Project name sanitization (Unicode support)
- Directory management
- Project search and listing
- Cleanup operations

#### 6. Debugger (`auto_forge_debugger.rb`)
- Selenium integration
- JavaScript error detection
- Performance metrics collection
- Functionality testing (web apps only, with retry + log filtering)

## API Usage Patterns

### Model Selection Logic

```ruby
# Orchestration uses models from MDSL:
# - gpt-5 for OpenAI
# - claude-sonnet-4-5-20250929 for Claude
# - grok-4-fast-reasoning for Grok
# Provider helpers route to the correct API automatically.

# Code generation is delegated to the provider-specific agent
call_gpt5_codex(prompt: prompt, app_name: 'AutoForge')          # OpenAI
claude_code_agent(prompt, 'AutoForgeClaude')                    # Claude
call_grok_code(prompt: prompt, app_name: 'AutoForgeGrok')       # Grok
```

### Responses API vs Chat API

1. **Orchestration (MDSL)**:
   - Uses models specified per app (`auto_forge_openai` vs `auto_forge_claude`)
   - Provider helpers (OpenAIHelper / ClaudeHelper) handle API routing
   - Manages tool calls and structured responses

2. **Code Generation (Provider Agents)**:
   - OpenAI Code via `OpenAICodeAgent` for OpenAI
   - Claude Code via `ClaudeCodeAgent` for Claude
   - Grok-Code-Fast-1 via `GrokCodeAgent` for Grok
   - All use the provider's Responses API with deterministic parameters
   - Provider-specific prompt builders optimize for each model's strengths
   - Output sanitizers ensure consistent artifacts across providers

## File Management

### Directory Structure
```
~/monadic/data/auto_forge/
├── [AppName]_[YYYYMMDD]_[HHMMSS]/
│   ├── index.html
│   └── context.json (for modifications)
```

### Unicode Handling
- Full UTF-8 support for project names
- Only filesystem-unsafe characters are replaced
- Japanese/Chinese/emoji characters preserved
- Example: "病気診断アプリ" → "病気診断アプリ_20240127_162936"

### Context Persistence
```json
{
  "original_spec": {
    "name": "TodoApp",
    "type": "productivity",
    "description": "...",
    "features": [...]
  },
  "created_at": "2024-01-27T16:29:36Z",
  "modified_at": "2024-01-27T17:15:22Z",
  "modification_count": 3
}
```

## Provider Variants & Progress Broadcasting

- Three MDSL apps wrap the shared tool layer:
  - `auto_forge_openai`: GPT-5 orchestration + OpenAI Code generation
  - `auto_forge_claude`: Claude Code 4.1 orchestration + generation
  - `auto_forge_grok`: Grok-4-Fast-Reasoning orchestration + Grok-Code-Fast-1 generation
- Provider agents emit `wait` fragments with `source` identifiers so the WebSocket layer can stream updates into the temp card:
  - `OpenAICodeAgent` for OpenAI
  - `ClaudeCodeAgent` for Claude
  - `GrokCodeAgent` for Grok
- Progress fragments optionally include `minutes`/`remaining` values; when missing, the UI still displays provider-specific status text.
- Web UI translation keys (`claudeOpusGenerating`, `grokCodeGenerating`, etc.) were added for every locale to keep progress messages localized.

### Grok-Specific Implementation Details

- **Orchestration Model**: Grok-4-Fast-Reasoning with `reasoning_effort: "medium"` for balanced quality and speed
- **Code Generation Model**: Grok-Code-Fast-1 (default in `GrokCodeAgent`)
- **Prompt Optimization**: Prompts emphasize "smaller, focused tasks" and "iterative development" to match Grok-Code-Fast-1's strengths
- **Performance**: 92 tokens/sec throughput, significantly faster than OpenAI Code
- **Cost**: 6-7x cheaper than OpenAI Code
- **Strengths**: HTML/CSS/JavaScript, SVG graphics, animations, visual components
- **Agent Files**:
  - `agents/grok_html_generator.rb`: HTML/CSS/JS generation
  - `agents/grok_cli_generator.rb`: CLI tool generation
  - Uses `GrokCodeAgent` mixin from `lib/monadic/agents/grok_code_agent.rb`

### CLI Optional File Suggestions

- `suggest_cli_additional_files` inspects the generated script to decide which optional files to offer:
  - README is suggested only when a README is absent.
  - Config templates trigger when the script references config parsers (`configparser`, YAML, `--config`, etc.).
  - Dependency manifests are offered when imports go beyond the per-language standard library set defined in `standard_libraries`.
  - Usage examples (USAGE.md) are suggested when argument parsing libraries (argparse, OptionParser, click, etc.) are detected.
  - A “custom asset” entry is always included to remind the orchestrator that arbitrary files can be generated on demand.
- `generate_additional_file` re-validates project context (project path, type, and main file) before writing to disk.
- Custom file requests require both `file_name` (sanitized to avoid traversal) and `instructions`. Content is produced through the provider agent (`codex_callback`, `call_gpt5_codex`, or `claude_code_agent`) using a rich prompt that includes the main script excerpt and existing files.

## Error Handling

### Common Error Patterns

1. **Model Errors**:
   - OpenAI Code returning chat responses → Fixed with proper prompt formatting
   - Temperature parameter errors → Removed for Responses API models
   - Model not found → Ensure API key has access

2. **Generation Errors**:
   - Placeholder HTML (173 bytes) → Mock generator conflict (resolved)
   - Empty response → Timeout or API issues
   - Long generation time → Normal for OpenAI Code / Claude Code (2-5 minutes)

3. **File System Errors**:
   - Unicode project names → Fixed with proper encoding
   - Directory creation failures → Check permissions
   - File not found → Verify project exists with list_projects

## Debugging Features

### Selenium Integration

```python
# Debug script workflow
1. Load HTML in headless Chrome
2. Collect browser console logs
3. Execute JavaScript tests
4. Measure performance metrics
5. Return structured report
```

### Debug Report Structure
```ruby
{
  success: true/false,
  summary: [...],
  javascript_errors: [...],
  warnings: [...],
  tests: [...],
  performance: {
    loadTime: ms,
    domReadyTime: ms,
    renderTime: ms
  },
  viewport: {width: px, height: px}
}
```

## Performance Considerations

### Generation Timing
- Simple apps: 30-60 seconds
- Medium complexity: 1-3 minutes
- Complex apps: 2-5 minutes
- Modifications: Usually faster than initial generation

### Optimization Strategies
1. Reuse existing content for modifications
2. Cache project lookups
3. Parallel tool execution where possible
4. Keep prompts concise to reduce generation time across providers

## Testing

### Unit Tests
```ruby
# spec/unit/apps/auto_forge_orchestrator_spec.rb
- Project orchestration logic
- Context management

# spec/unit/apps/auto_forge_html_generator_spec.rb
- HTML generation and validation

# spec/unit/apps/auto_forge_codex_response_analyzer_spec.rb
- Codex response parsing and analysis

# spec/unit/apps/auto_forge_error_explainer_spec.rb
- Error message generation

# spec/unit/apps/auto_forge_cli_additional_files_spec.rb
- CLI optional file suggestion heuristics

# spec/unit/apps/auto_forge_tools_diagnosis_spec.rb
- Tool diagnostic functionality
```

### Integration Tests
See system tests for end-to-end workflows

## Known Limitations

1. **API Constraints**:
   - OpenAI Code requires Responses API
   - No streaming for complex generations
   - Rate limits apply

2. **File Constraints**:
   - Single HTML file output
   - No external dependencies
   - Client-side only

3. **Selenium Constraints**:
   - Requires Docker container
   - File:// protocol limitations
   - Headless Chrome restrictions

## Maintenance Notes

### When Updating Models
1. Check `model_spec.js` for API type configuration
2. Verify Responses API compatibility
3. Test both orchestration and code generation
4. Update documentation

### When Adding Features
1. Update MDSL tool definitions
2. Implement in `auto_forge_tools.rb`
3. Add tests
4. Update both public and internal docs

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Model not found" | Wrong model name or no access | Check API key permissions |
| Slow generation | Normal for OpenAI Code | Add progress indicators |
| Empty HTML | API timeout | Increase timeout settings |
| Unicode errors | Encoding issues | Ensure UTF-8 throughout |
| Selenium failures | Container not running | Check Docker status |

## Security Considerations

1. **API Keys**: Never log or expose in generated code
2. **File Access**: Restricted to auto_forge directory
3. **Code Execution**: Selenium runs in sandboxed container
4. **User Input**: Sanitized for filesystem operations
5. **Generated Code**: No server-side execution capabilities
