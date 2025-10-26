# September 2025 Improvements

## GPT-5-Codex and Grok-Code Agent Integration

### Overview
Implemented agent architecture pattern for complex code generation, where main conversational models delegate specialized code generation tasks to dedicated models.

### Changes

#### 1. GPT-5-Codex Access Simplification
- **Previous**: Complex model list checking
- **Current**: Simple API key presence check
- **Reason**: All OpenAI API key holders have access to GPT-5-Codex

#### 2. Grok-Code-Fast-1 Agent Implementation
- Created `Monadic::Agents::GrokCodeAgent` module
- Parallel to GPT-5-Codex implementation
- Integrated into all Grok coding apps:
  - Code Interpreter Grok
  - Coding Assistant Grok
  - Jupyter Notebook Grok
  - Research Assistant Grok

#### 3. Model Configuration Fixes
- Changed Grok apps from using `grok-code-fast-1` as main model to `grok-4-fast-reasoning`
- Grok-Code-Fast-1 now properly used only for code generation via agent
- Fixes 400 errors when using tools with grok-code-fast-1

## Jupyter Notebook Improvements

### Japanese Font Support
- Automatic configuration of Japanese fonts for matplotlib
- Injected font setup cell at notebook creation
- Suppresses "Glyph missing from font" warnings
- Uses Noto Sans CJK JP font

### File Name Handling
- Fixed issue where `.ipynb` extension was always added
- Now handles both formats correctly:
  - `notebook_20250925_051036.ipynb` (with extension)
  - `notebook_20250925_051036` (without extension)
- Applies to all Jupyter Notebook variants (OpenAI, Claude, Gemini, Grok)

## Coding Assistant File Operations

### Universal File Operation Support
Added file operations to ALL Coding Assistant variants:
- `read_file_from_shared_folder` - Read files from shared folder
- `write_file_to_shared_folder` - Write/append files to shared folder
- `list_files_in_shared_folder` - List directory contents

### Supported Providers
- ✅ OpenAI (+ GPT-5-Codex agent)
- ✅ Claude
- ✅ Gemini
- ✅ Grok (+ Grok-Code agent)
- ✅ Cohere
- ✅ Mistral
- ✅ DeepSeek
- ✅ Perplexity

## Configuration and Documentation

### Configuration Priority Documentation
Added to `docs/reference/configuration.md`:
1. Environment variables (highest priority)
2. `system_defaults.json`
3. Hardcoded defaults (lowest priority)

### Development Guidelines
Updated `CLAUDE.md` with:
- Code quality guidelines
- Language usage rules (Japanese comments with English identifiers)
- GPT-5-Codex access notes
- Configuration priority documentation

### New Documentation
- Internal developer documentation for agent architecture patterns
- `docs/release_notes/2025_09_improvements.md` - This file

## Testing

### New Test Coverage
- `spec/unit/adapters/jupyter_helper_spec.rb` - Jupyter file handling tests
- `spec/unit/apps/coding_assistant_tools_spec.rb` - Coding Assistant file operations
- Existing: `spec/unit/agents/gpt5_codex_agent_spec.rb`
- Existing: `spec/unit/agents/grok_code_agent_spec.rb`

### Test Focus Areas
- File extension handling
- Japanese font configuration
- Agent access checking
- File path validation
- Error handling

## Breaking Changes
None - all changes are backward compatible

## Migration Notes
No migration required. All improvements are automatically available after update.