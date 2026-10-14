# Auto Forge Internals

## Overview

Auto Forge (MDSL `display_name` "Auto Forge") generates applications in two layers: an orchestrator model, and a code agent of the same provider.

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
│  (OpenAI / Anthropic / xAI chat models       │
│   via provider APIs)                         │
│   - User interaction                         │
│   - Planning & coordination                  │
│   - Tool invocation                          │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│         Tool Methods Layer                   │
│         (auto_forge_tools.rb)                │
│   - generate_application, debug_application  │
│   - list_projects, validate_specification    │
│   - generate_additional_file, finish_task    │
│   - <provider>_code_agent                    │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│        Code Generation Layer                 │
│  (OpenAI / Claude / Grok                     │
│   provider-specific coding agents)           │
│   - HTML/CSS/JS/CLI generation               │
│   - Same provider as the orchestrator        │
└──────────────────────────────────────────────┘
```

### Key Components

#### 1. MDSL Configuration (`auto_forge_openai.mdsl`, `auto_forge_claude.mdsl`, `auto_forge_grok.mdsl`)
- Defines the app interface and system prompt for each provider
- Configures available models for each provider (orchestration + code generation)
- Check the actual MDSL files for current model configurations
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
- **Project resolution fallback**: When `debug_application` is called without a project name (e.g., `debug_application({})`), `resolve_project_context` falls back to the most recently created project with an `index.html`. so `debug_application({})` targets the latest project; when that project has no `index.html`, the result is `error_type: :missing_name`.

#### 3. Application Logic (`auto_forge.rb`)
- Main application class
- Manages project lifecycle
- Handles file operations
- Context persistence for modifications

#### 4. HTML Generators
- **OpenAI**: `agents/html_generator.rb` with OpenAICodeAgent
- **Claude**: Uses `agents/html_generator.rb` with ClaudeCodeAgent callback - Interfaces with Claude models via claude_code_agent
- **Grok**: `agents/grok_html_generator.rb` with GrokCodeAgent
- The code agents use the provider's default code model (`providerDefaults` code entry, `ModelSpec.default_code_model`); OpenAI and Grok can be overridden by argument, MDSL or `OPENAI_CODE_MODEL` / `GROK_CODE_MODEL`
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
# Orchestration uses models from MDSL (check actual files for current models)
# Provider helpers route to the correct API automatically.

# Code generation is delegated to the provider-specific agent
call_openai_code(prompt: prompt, app_name: 'AutoForge')         # OpenAI
claude_code_agent(prompt, 'AutoForgeClaude')                    # Claude
call_grok_code(prompt: prompt, app_name: 'AutoForgeGrok')       # Grok
```

### Responses API vs Chat API

1. **Orchestration (MDSL)**:
   - Uses models specified per app (`auto_forge_openai` vs `auto_forge_claude`)
   - Provider helpers (OpenAIHelper / ClaudeHelper) handle API routing
   - Manages tool calls and structured responses

2. **Code Generation (Provider Agents)**:
   - `OpenAICodeAgent` (OpenAI), `ClaudeCodeAgent` (Claude), `GrokCodeAgent` (Grok)
   - Claude calls `send_query` (Messages API, temperature 0.3, reasoning effort medium); OpenAI and Grok go through `api_request`
   - Provider-specific prompt builders optimize for each model's strengths
   - Output sanitizers ensure consistent artifacts across providers

## File Management

### Directory Structure
```
~/monadic/data/auto_forge/
├── [AppName]_[YYYYMMDD]_[HHMMSS]/
│   ├── index.html
│   └── .autoforge.json (metadata: created_at, project_name, base_name, …)
├── .backups/
└── .templates/
```

### Unicode Handling
- Full UTF-8 support for project names
- Only filesystem-unsafe characters are replaced
- Japanese/Chinese/emoji characters preserved
- Example: "病気診断アプリ" → "病気診断アプリ_YYYYMMDD_HHMMSS"

### Context Persistence

The context for modifications is kept in the session, under `@context[:auto_forge]`. The project folder holds `.autoforge.json` with the project metadata.

## Provider Variants & Progress Broadcasting

- Three MDSL apps wrap the shared tool layer:
  - `auto_forge_openai`: OpenAI orchestration + code generation
  - `auto_forge_claude`: Claude orchestration + code generation
  - `auto_forge_grok`: Grok orchestration + code generation
- Provider agents emit `wait` fragments with `source` identifiers so the WebSocket layer can stream updates into the temp card:
  - `OpenAICodeAgent` for OpenAI
  - `ClaudeCodeAgent` for Claude
  - `GrokCodeAgent` for Grok
- Progress fragments optionally include `minutes`/`remaining` values; when missing, the UI still displays provider-specific status text.
- Progress text uses translation keys such as `claudeOpusGenerating` and `grokCodeGenerating` (`public/js/i18n/translations.js`).

### Grok-Specific Implementation Details

- **Orchestration**: `reasoning_effort "low"` (Claude: `"low"`, OpenAI: `"none"`)
- **Code Generation Model**: the default code model for xAI (`GrokCodeAgent`)
- **Prompts**: ask for smaller, focused tasks and iterative development
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
- Custom file requests require both `file_name` (sanitized to avoid traversal) and `instructions`. Content is produced through `context[:codex_callback]`, which wraps `call_openai_code`, `claude_code_agent` or `call_grok_code`, using a rich prompt that includes the main script excerpt and existing files.

## Error Handling

### Common Error Patterns

1. **Model Errors**:
   - Model not found → Ensure API key has access

2. **Generation Errors**:
   - Empty response → Timeout or API issues
   - Time limits: OpenAI code agent 1200 s (`OPENAI_CODE_TIMEOUT`), Grok 300 s (`GROK_CODE_TIMEOUT`)

3. **File System Errors**:
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

Also: `auto_forge_claude_advisor_integration_spec.rb`, `auto_forge_debugger_spec.rb`, `auto_forge_finish_task_spec.rb`, `auto_forge_project_path_spec.rb` (same folder).

### Integration Tests
`spec/integration/apps/auto_forge_debug_integration_spec.rb` and `auto_forge_diagnosis_integration_spec.rb`

## Known Limitations

1. **API Constraints**:
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
1. Check `model_spec.js` for the model's `api_type` and code-model entries
2. Test both orchestration and code generation
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
| Slow generation | Long code generation | Progress is shown in the temp card |
| Empty HTML | API timeout | Increase timeout settings |
| Unicode errors | Encoding issues | Ensure UTF-8 throughout |
| Selenium failures | Container not running | Check Docker status |

## Security Considerations

1. **API Keys**: Never log or expose in generated code
2. **File Access**: Restricted to auto_forge directory
3. **Code Execution**: Selenium runs in sandboxed container
4. **User Input**: Sanitized for filesystem operations
5. **Generated Code**: No server-side execution capabilities
