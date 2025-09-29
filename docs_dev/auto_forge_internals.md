# AutoForge Internal Documentation

## Overview

AutoForge (public name: "Artifact Builder") is a sophisticated multi-layer application generation system that combines GPT-5 or Claude Opus orchestration with provider-specific code generation (GPT-5-Codex or Claude Opus).

## Architecture

### Layer Architecture

```
┌─────────────────────────────────────┐
│         MDSL Framework              │
│ (auto_forge_openai/claude.mdsl)     │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│      Orchestration Layer            │
│   (GPT-5 / Claude Opus via API)     │
│   - User interaction                │
│   - Planning & coordination         │
│   - Tool invocation                 │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│      Tool Methods Layer             │
│    (auto_forge_tools.rb)            │
│   - generate_application            │
│   - debug_application               │
│   - list_projects                   │
│   - validate_specification          │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│    Code Generation Layer            │
│ (GPT-5-Codex / Claude Opus API)     │
│   - HTML/CSS/JS/CLI generation      │
│   - via provider agents             │
└─────────────────────────────────────┘
```

### Key Components

#### 1. MDSL Configuration (`auto_forge_openai.mdsl`, `auto_forge_claude.mdsl`)
- Defines the app interface and system prompt for each provider
- Configures available models (GPT-5/GPT-5-Codex for OpenAI, Claude Opus 4.1 for Claude)
- Registers tool methods, including `generate_additional_file`
- Uses the provider's chat/responses API for orchestration

#### 2. Tool Methods (`auto_forge_tools.rb`)
- Implements the core logic for each tool
- Includes `GPT5CodexAgent` and `ClaudeOpusAgent` for provider-specific code generation
- Handles project management, optional CLI asset generation, and file I/O
- Coordinates between orchestration and code generation

#### 3. Application Logic (`auto_forge.rb`)
- Main application class
- Manages project lifecycle
- Handles file operations
- Context persistence for modifications

#### 4. HTML Generator (`agents/html_generator.rb`)
- Interfaces with GPT-5-Codex
- Builds prompts for code generation
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
# Orchestration uses models from MDSL (GPT-5/GPT-5-Codex for OpenAI, Claude Opus for Claude)
# Provider helpers route to the correct Responses API automatically.

# Code generation is delegated to the provider-specific agent
call_gpt5_codex(prompt: prompt, app_name: 'AutoForge')          # OpenAI
claude_opus_agent(prompt, 'AutoForgeClaude')                    # Claude
```

### Responses API vs Chat API

1. **Orchestration (MDSL)**:
   - Uses models specified per app (`auto_forge_openai` vs `auto_forge_claude`)
   - Provider helpers (OpenAIHelper / ClaudeHelper) handle API routing
   - Manages tool calls and structured responses

2. **Code Generation (Provider Agents)**:
   - GPT-5-Codex via `GPT5CodexAgent` for OpenAI
   - Claude Opus via `ClaudeOpusAgent` for Claude
   - Both use the provider's Responses API with deterministic parameters
   - Shared prompt builders and output sanitizers ensure consistent artifacts

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
- Example: "病気診断アプリ" → "病気診断アプリ_20250127_162936"

### Context Persistence
```json
{
  "original_spec": {
    "name": "TodoApp",
    "type": "productivity",
    "description": "...",
    "features": [...]
  },
  "created_at": "2025-01-27T16:29:36Z",
  "modified_at": "2025-01-27T17:15:22Z",
  "modification_count": 3
}
```

## Provider Variants & Progress Broadcasting

- Two MDSL apps wrap the shared tool layer: `auto_forge_openai` (GPT-5 orchestration + GPT-5-Codex generation) and `auto_forge_claude` (Claude Opus 4.1 orchestration + generation).
- `Monadic::Agents::ClaudeOpusAgent` mirrors the GPT-5-Codex contract by emitting `wait` fragments with `source: "ClaudeOpusAgent"` so the WebSocket layer can stream updates into the temp card.
- Progress fragments optionally include `minutes`/`remaining` values; when missing, the UI still displays provider-specific status text.
- Web UI translation keys (`claudeOpusGenerating`, etc.) were added for every locale to keep progress messages localized.

### CLI Optional File Suggestions

- `suggest_cli_additional_files` inspects the generated script to decide which optional files to offer:
  - README is suggested only when a README is absent.
  - Config templates trigger when the script references config parsers (`configparser`, YAML, `--config`, etc.).
  - Dependency manifests are offered when imports go beyond the per-language standard library set defined in `standard_libraries`.
  - Usage examples (USAGE.md) are suggested when argument parsing libraries (argparse, OptionParser, click, etc.) are detected.
  - A “custom asset” entry is always included to remind the orchestrator that arbitrary files can be generated on demand.
- `generate_additional_file` re-validates project context (project path, type, and main file) before writing to disk.
- Custom file requests require both `file_name` (sanitized to avoid traversal) and `instructions`. Content is produced through the provider agent (`codex_callback`, `call_gpt5_codex`, or `claude_opus_agent`) using a rich prompt that includes the main script excerpt and existing files.

## Error Handling

### Common Error Patterns

1. **Model Errors**:
   - GPT-5-Codex returning chat responses → Fixed with proper prompt formatting
   - Temperature parameter errors → Removed for Responses API models
   - Model not found → Ensure API key has access

2. **Generation Errors**:
   - Placeholder HTML (173 bytes) → Mock generator conflict (resolved)
   - Empty response → Timeout or API issues
   - Long generation time → Normal for GPT-5-Codex / Claude Opus (2-5 minutes)

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
# spec/unit/apps/auto_forge_spec.rb
- Project name sanitization
- Context persistence
- File operations
- Error handling

# spec/unit/apps/auto_forge/auto_forge_cli_additional_files_spec.rb
- CLI optional file suggestion heuristics
- Additional file generation guardrails
```

### Integration Tests
```ruby
# spec/integration/apps/auto_forge_integration_spec.rb
- End-to-end generation
- Modification workflow
- Selenium debugging
- API interactions
```

## Known Limitations

1. **API Constraints**:
   - GPT-5-Codex requires Responses API
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

## Future Enhancements

1. **Multi-file Support**: Generate complete web applications with separate files
2. **Framework Support**: Allow React, Vue, or other frameworks
3. **Server-side Code**: Generate Node.js/Python backends
4. **Version Control**: Built-in git integration for projects
5. **Deployment**: Direct deployment to cloud platforms
6. **Collaborative Editing**: Multi-user project modification

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
| Slow generation | Normal for GPT-5-Codex | Add progress indicators |
| Empty HTML | API timeout | Increase timeout settings |
| Unicode errors | Encoding issues | Ensure UTF-8 throughout |
| Selenium failures | Container not running | Check Docker status |

## Security Considerations

1. **API Keys**: Never log or expose in generated code
2. **File Access**: Restricted to auto_forge directory
3. **Code Execution**: Selenium runs in sandboxed container
4. **User Input**: Sanitized for filesystem operations
5. **Generated Code**: No server-side execution capabilities
