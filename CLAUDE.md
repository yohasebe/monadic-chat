# Maintainers Guide (Internal)

Note: This file is intentionally ignored by Git (.gitignore). Do not commit or push this file. Update locally only.

This document provides internal guidance for contributors working in this repository.

Policy: Do not reference external assistant products (e.g., “Claude Code”, “Codex CLI”) anywhere in implementation code, public documentation, tests, or commit messages. Do not surface references to this file from runtime logs or test output.

## Commit & Push Policy

- Commit messages MUST be in English only (no mixed-language text). Use short English commit subjects (concise, imperative).
- Do not mention external assistant products (e.g., "Claude Code", "Codex CLI") in commit messages.
- Do not include co-authorship credits or generation tool references in commit messages.
- Do not reference internal files like `AGENTS.md` or `CLAUDE.md` in commit messages.
- **IMPORTANT: Keep commit messages simple and concise (one line strongly preferred).**
  - ❌ Bad: Multi-paragraph messages with "Key changes:", "Technical implementation:", bullet points, or detailed explanations
  - ✅ Good: Single line describing what changed (e.g., "Add Web UI STT model selection with diarization support")
  - Rationale: Detailed information belongs in code, PRs, and documentation, not commit messages
  - Long messages reduce git log readability and are rarely read in practice
- Do not commit without explicit user approval.
- Do not push without explicit user approval.

## Project Overview

Monadic Chat is a locally hosted web application that creates intelligent chatbots by providing Linux environments on Docker to LLMs. It consists of:
- **Electron desktop app** (main entry point)
- **Ruby backend service** (Rack-based web app)
- **Docker containers** (Ruby, Python, PostgreSQL/PGVector, Selenium)
- **Native Ollama** (connects to host OS Ollama via `host.docker.internal:11434`)
- **Web frontend** (JavaScript/HTML with WebSocket communication)

## Essential Commands

### Development
```bash
# Start the application (Electron)
npm start

# Start backend server only (for debugging)
rake server:debug  # or ./bin/monadic_server.sh debug

# Run all tests
npm test           # Frontend tests
rake spec          # Ruby tests (auto-starts required containers)

# Run specific test suites
npm run test:watch # Frontend tests with watch mode
rake spec_unit     # Ruby unit tests (no Docker required)
rake spec_integration # Ruby integration tests
rake spec_system   # Ruby system tests

# Linting
npx eslint .       # JavaScript
bundle exec rubocop # Ruby (from docker/services/ruby)

# Build packages (macOS is Apple Silicon only, Intel Mac not supported)
npm run build:mac-arm64   # Mac ARM64 (Apple Silicon)
npm run build:win         # Windows
npm run build:linux-x64   # Linux x64
```

### API Configuration
API keys and settings are stored in `~/monadic/config/env`:
```
# API Keys
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
GEMINI_API_KEY=...
COHERE_API_KEY=...
MISTRAL_API_KEY=...
PERPLEXITY_API_KEY=...
GROQ_API_KEY=...
XAI_API_KEY=...

# Optional Settings
OPENAI_VECTOR_STORE_ID=...  # Reuse existing Vector Store
PDF_DEFAULT_STORAGE=local   # or 'cloud' for OpenAI Vector Store
EXTRA_LOGGING=true          # Enable detailed logging
```

User-specific model overrides can be defined in `~/monadic/config/models.json`.

## Version Management

### Single Source of Truth

Version numbers are managed through a single source of truth to prevent sync issues:

**Primary Version Source:**
- `services/ruby/lib/monadic/version.rb` - The authoritative version definition (always available)

**Derived Sources:**
- `package.json` - npm package version (must match version.rb, used by Electron)
- `docker/monadic.sh` - Reads version dynamically from `version.rb` at runtime

**How it works:**
```bash
# monadic.sh (lines 6-29)
VERSION_FILE="${SCRIPT_DIR}/services/ruby/lib/monadic/version.rb"
if [ -f "$VERSION_FILE" ]; then
  # Extract version from Ruby file: VERSION = "1.0.0-beta.4"
  export MONADIC_VERSION=$(grep 'VERSION = ' "$VERSION_FILE" | sed -E 's/.*VERSION = "([^"]+)".*/\1/')
else
  # Fallback: try package.json (development environment only)
  # ... fallback logic ...
fi
```

**Version Update Process:**
1. Update version in `services/ruby/lib/monadic/version.rb` (e.g., `1.0.0-beta.3` → `1.0.0-beta.4`)
2. Update version in `package.json` to match
3. `docker/monadic.sh` automatically reads from `version.rb` - no manual update needed
4. Docker images are automatically tagged with the new version
5. On app startup, version mismatch triggers automatic Ruby container rebuild (with cache)

**Benefits:**
- Works in both development and packaged app environments
- No dependency on `jq` (uses standard grep/sed)
- version.rb is always included in Docker images
- Automatic version detection eliminates manual updates in monadic.sh
- Version-based rebuild detection works correctly

## Architecture

### Core Components

1. **Electron App** (`/`)
   - Entry: `main.js`, `mainScreen.js`
   - IPC communication between main/renderer processes
   - WebView for hosting the Ruby web interface
   - Auto-updater functionality

2. **Ruby Backend** (`docker/services/ruby/`)
   - Rack application (`config.ru`)
   - WebSocket server for real-time communication
   - Monadic DSL for app definitions (`lib/monadic/dsl.rb`)
   - Vendor adapters for AI providers (`lib/monadic/adapters/vendors/`)
   - Apps directory with 20+ specialized applications (`apps/`)

3. **Frontend JavaScript** (`docker/services/ruby/public/js/`)
   - WebSocket client (`monadic/websocket.js`)
   - UI components (`monadic/ui/`)
   - Shared components (`monadic/shared/`)
   - Application-specific modules (`monadic/apps/`)

4. **Docker Services** (`docker/services/`)
   - Ruby container: Main application server
   - Python container: JupyterLab and Python-based tools
   - PostgreSQL/PGVector: Vector database for embeddings
   - Selenium: Web scraping capabilities
   - Ollama: Local LLM support (native on host OS, connects via `host.docker.internal:11434`)

### Key Design Patterns

1. **Monadic Context Management**: Apps can maintain structured JSON context across conversations, enabling stateful interactions with reasoning process tracking.

2. **Vendor Abstraction**: All AI providers (OpenAI, Claude, Gemini, etc.) share common interfaces through vendor helpers in `lib/monadic/adapters/vendors/`.

3. **DSL-Based App Definition**: Applications are defined using a declarative DSL that specifies properties, methods, and behaviors. See `docs/advanced-topics/monadic_dsl.md` for details.

4. **Error Pattern Detection**: Automatic detection and handling of common error patterns (infinite loops, rate limits, etc.) via `ErrorPatternDetector`.

5. **Single Source of Truth (SSOT)**: Model capabilities are centralized in `model_spec.js` with Ruby-side accessors via `ModelSpec`. See `docs_dev/developer/model_spec_vocabulary.md` for the canonical vocabulary.

6. **PDF Storage Abstraction**: Supports both local PGVector and OpenAI Vector Store for PDF document management. The system automatically routes to the appropriate storage based on user selection.

7. **Thinking/Reasoning Process Display**: Multiple AI providers expose their internal reasoning process. Monadic Chat captures and displays this separately from the main response. See `docs_dev/ruby_service/thinking_reasoning_display.md` for implementation details.

### SSL Configuration & Provider Fallbacks
- `docker/services/ruby/lib/monadic/utils/ssl_configuration.rb` disables OpenSSL CRL checks (`V_FLAG_CRL_CHECK`, `V_FLAG_CRL_CHECK_ALL`) at startup and sets the same `SSLContext` on `HTTP.default_options` for all `http` gem requests.
- Setting `SSL_CERT_FILE` / `SSL_CERT_DIR` in `.env` allows using a custom CA. Without these, the system default certificate store is used.
- Model list fetching is wrapped by `Monadic::Utils::ProviderModelCache.fetch`, which falls back to MDSL `model`/`models` and `providerDefaults` on API failure. With `EXTRA_LOGGING=true`, fallback events are logged as `[ProviderModelCache] ... fallback`.

### Communication Flow
```
Electron App → WebView → Ruby Web Server ← WebSocket → Browser Client
                              ↓
                        Docker Containers
                     (Tools & Environments)
```

## Testing Approach

- **Frontend**: Jest with jsdom, test files in `test/frontend/*.test.js`
- **Ruby**: RSpec with unit/integration/system separation
- **Coverage**: Run `npm run test:coverage` for frontend, check Ruby coverage in CI
- **Test Helpers**: Shared utilities in `test/helpers.js` (frontend) and `spec/support/` (Ruby)

### Philosophy for API-facing tests
- Avoid strict string equality for provider responses; assert presence/shape instead.
- Prefer simple invariants (non-empty text, valid JSON) over exact phrasing.
- Consider transient provider errors non-fatal in smoke/matrix specs; these tests gate integration, not provider uptime.

## Development Notes

- The app automatically manages Docker containers lifecycle
- WebSocket connections handle real-time AI responses and streaming
- Each AI provider has specific adapters handling their unique APIs and features
- The shared folder (`~/monadic/data`) syncs between host and Docker containers
- Voice features use browser Web Speech API or provider-specific TTS/STT

### Dual-Mode Execution (CRITICAL — read before modifying path-related code)

Monadic Chat runs in two distinct modes with **different file path resolution**:

**Production Mode** (`npm start` / Electron):
- Ruby code runs **inside** the Docker Ruby container
- `in_container?` returns `true`
- Shared volume: `/monadic/data` (container path)
- Scripts: `/monadic/scripts` (container path)
- `send_command` executes commands in peer containers via `docker exec`

**Development Mode** (`rake server:debug`):
- Ruby code runs **locally** on the host machine (Ruby container is stopped)
- Other containers (Python, PGVector, Selenium) run in Docker
- `in_container?` returns `false`
- Shared volume: `~/monadic/data` (host path)
- Scripts: relative path from source tree
- `send_command` executes commands via `docker exec` into running containers

**Path Resolution Mechanism** (`lib/monadic/utils/environment.rb`):
- `Monadic::Utils::Environment.in_container?` detects mode via `/.dockerenv` file
- `resolve_path('/monadic/data')` returns the correct path for current mode
- Constants: `SHARED_VOL = "/monadic/data"` (container) vs `LOCAL_SHARED_VOL = ~/monadic/data` (host)

**Rules when writing path-related code**:
1. **Always use `Monadic::Utils::Environment.shared_volume`** (or `data_path`) instead of hardcoded paths
2. If you must use constants, use both `SHARED_VOL` and `LOCAL_SHARED_VOL` with `in_container?` guard
3. **File operations on shared data**: Use `Environment.resolve_path` or check both paths
4. **Docker exec commands**: Always go through `send_command` which handles container targeting
5. **Never assume** `/monadic/data` exists on the host or `~/monadic/data` exists in the container

### MCP (Model Context Protocol) Integration

Monadic Chat provides an MCP server that exposes all app tools via JSON-RPC 2.0, enabling external AI assistants to access Monadic Chat functionality.

**Claude Code Integration:**
- Connect Claude Code to Monadic Chat's PGVector documentation database
- Access semantic search across internal/external documentation
- Setup: `claude mcp add --scope user --transport stdio monadic-chat -- ruby ~/monadic/scripts/mcp_stdio_wrapper.rb`
- See `docs/advanced-topics/mcp-integration.md` for public documentation
- See `docs_dev/developer/claude_code_mcp_integration.md` for implementation details

**Configuration:**
```bash
# Enable in ~/monadic/config/env
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

**Testing:**
```bash
# Verify MCP server is running
curl http://localhost:3100/health

# List available tools
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

### Docker Desktop Management

- **Startup Requirement**: Docker Desktop must be running before executing `rake server:debug` or `./bin/monadic_dev start`
- **Auto-Start**: Use `electron .` to automatically start Docker Desktop (Electron app handles this)
- **Manual Start**: For CLI-only usage, start Docker Desktop manually before running server commands
- **Important**: Avoid running `docker` commands before Docker Desktop is fully initialized, as this may interfere with the startup process

### On-Demand Container Startup

Python and Selenium containers use **Docker Compose Profiles** and are NOT started by default:
- `docker compose up` starts only **Ruby + PGVector**
- When the user selects an app that needs Python (e.g., Code Interpreter, Jupyter), the container is started automatically in the background
- When the user selects an app that needs Selenium (e.g., Web Insight, AutoForge), both Python and Selenium are started
- Container dependencies are determined by `Monadic::Utils::ContainerDependencies` based on MDSL settings
- Manual startup: `monadic.sh ensure-service python|selenium`
- All containers are stopped together on app exit (`docker compose stop`)

### Container Build Strategies and Caching

**Ruby Container:**
- **Version Update (START button)**: Uses cache for fast rebuild (~1-2 min)
  - Automatic when app version changes (e.g., beta.4 → beta.5)
  - Cache is safe because only app code changes, not dependencies
- **Manual Build (Menu)**: Uses `--no-cache` for complete rebuild (~5-10 min)
  - Triggered by **Actions → Build Ruby Container**
  - Ensures clean build when needed

**Python Container:**
- **Install Options**: Configure packages (LaTeX, NLTK, spaCy, etc.) via **Actions → Install Options**
- **Smart Caching**: Detects option changes and uses `--no-cache` only when needed
  - Options unchanged: Fast rebuild (~1-2 min)
  - Options changed: Complete rebuild (~15-30 min)
- **Auto-Restart**: Container automatically restarts after rebuild to use new image
- **Configuration**: Settings stored in `~/monadic/config/env`
- **Tracking**: Previous build options saved in `~/monadic/log/python_build_options.txt`

**Key Principle:** Automatic rebuilds use cache (fast), manual builds from menu use `--no-cache` (reliable)

**Details**: See `docs_dev/docker-build-caching.md` for complete documentation

### Test File Path Conventions

- Test files in `spec/unit/` and `spec/integration/` use `require_relative '../../../'` to access `apps/` and `lib/` directories
- When adding new test files, follow existing path patterns for consistency
- Example: `spec/unit/apps/my_app_spec.rb` → `require_relative '../../../apps/my_app/my_app_tools'`

## Documentation Policy

### Documentation Structure and Content Guidelines

**Three Documentation Locations:**

1. **`docs/` - Public Documentation**
   - **Audience**: End users and app developers
   - **Content**: Feature descriptions, usage guides, API references, specifications, limitations that users need to know
   - **What to include**: Stable, documented features with clear usage instructions
   - **What NOT to include**: TODO items, unresolved issues, experimental feature details, implementation debates

2. **`docs_dev/` - Internal Documentation**
   - **Audience**: Monadic Chat maintainers and contributors
   - **Content**: Implementation explanations, architecture decisions, technical constraints, build/test infrastructure
   - **What to include**: Established design patterns, why specific approaches were chosen, technical implementation notes
   - **What NOT to include**: TODO items, unresolved issues, pending decisions, work-in-progress proposals

3. **`tmp/memo/` - Temporary Notes**
   - **Audience**: Current developers working on active tasks
   - **Content**: TODO lists, unresolved issues, implementation ideas being explored, work-in-progress notes
   - **What to include**: Anything temporary that doesn't belong in permanent documentation
   - **Lifecycle**: Delete or migrate to proper documentation once resolved

**Language Guidelines for Public Documentation:**
- Use clear, factual language without subjective assessments
- Describe features straightforwardly (what they do, how to use them, their constraints)
- Limitations are acceptable when they help users understand the feature scope
- Avoid speculative language ("may", "might", "could") for documented features
- Do not mark stable features as "experimental" or "beta" - if a feature is documented publicly, it's considered stable

**Examples:**
- ✅ "AutoForge creates single-file HTML applications"
- ✅ "Veo 3.1 supports 16:9 aspect ratio"
- ❌ "AutoForge is limited to single-file applications (this is a known limitation we're working to address)"
- ❌ "Multiple browser tabs (experimental feature, use at your own risk)"

**Model Name References:**
- Avoid hardcoding specific model IDs (e.g., `claude-opus-4-6`, `gpt-5-0125`) in documentation prose or code examples
- Use capability flag names (`supports_thinking`, `supports_adaptive_thinking`) or generic placeholders instead
- Model-specific details belong in `model_spec.js` (SSOT), not in prose documentation
- This reduces maintenance cost when models are added, renamed, or retired

**EN/JA Documentation Parity (CRITICAL):**
- Public documentation (`docs/`) is maintained in both English and Japanese (`docs/ja/`)
- **Every change to `docs/` MUST have a corresponding change in `docs/ja/`**, and vice versa
- This applies to ALL documentation changes: new sections, content updates, structural reorganization, feature descriptions
- Section headings and structure must match between EN and JA counterparts
- Run `npm run test:docs-parity` to verify heading structure parity before committing documentation changes
- This rule is NOT limited to model updates — it applies to every documentation change without exception

## Important Documentation References

### Internal Developer Documentation
- **SSOT Implementation**: `docs_dev/developer/model_spec_vocabulary.md` - Canonical model capability vocabulary
- **Testing Guide**: `docs_dev/developer/testing_guide.md` - Comprehensive testing approach
- **Code Structure**: `docs/advanced-topics/code_structure.md` - Detailed architecture overview
- **Development Workflow**: `docs_dev/developer/development_workflow.md` - Best practices

### Internal Documentation (docs_dev/)
- **SSOT Normalization**: `docs_dev/ssot_normalization_and_accessors.md` - Model spec normalization layer
- **Docker Architecture**: `docs_dev/docker-architecture.md` - Container orchestration details
- **Docker Build Caching**: `docs_dev/docker-build-caching.md` - Install options, smart caching, auto-restart
- **Logging**: `docs_dev/logging.md` - Debug and trace logging configuration
- **Common Issues**: `docs_dev/common-issues.md` - Troubleshooting guide
- **Unified Test Runner**: `docs_dev/test_runner.md` - Orchestration, artifacts, and options
- **AutoForge Internals**: `docs_dev/auto_forge_internals.md` - Artifact Builder architecture and implementation
- **File Inputs API**: `docs_dev/developer/file_inputs_api.md` - OpenAI File Inputs integration, file_id caching, extended formats

## Common Tasks

### Adding a New AI Provider

**Checklist** (all items required):
1. Create vendor helper in `lib/monadic/adapters/vendors/` (implement `list_models`, `send_query`, `clear_models_cache`)
2. Add entry to `ProviderConfig::PROVIDER_INFO` in `lib/monadic/dsl.rb` (helper_module, api_key, default_model_env, display_group, aliases)
3. Add entry to `FORMATTERS` hash in `lib/monadic/dsl.rb`
4. Add model specifications to `public/js/monadic/model_spec.js`
5. Add API key case to `monadic.rb` provider key mapping (~L96)
6. Update frontend `getProviderFromGroup()` in `public/js/monadic.js`
7. Update `agents/ai_user_agent.rb` provider mappings (keywords, API key, default model)
8. Update `agents/second_opinion_agent.rb` if second-opinion should support the provider
9. Update `agents/context_extractor_agent.rb` if context extraction should support the provider
10. Add tests for the new vendor
11. Update `providerDefaults` in `model_spec.js` with default model for the provider

**Key rule**: Use `ProviderConfig` for provider name resolution. Do NOT add new ad-hoc `.include?()` chains.

### Creating a New App
1. Create app directory in `docker/services/ruby/apps/`
2. Define app using Monadic DSL (`.mdsl` file) or Ruby class (see `docs/advanced-topics/monadic_dsl.md`)
3. Add frontend UI if needed in `docker/services/ruby/public/js/monadic/apps/`
4. App is auto-registered during startup

### AutoForge / Artifact Builder
- **Purpose**: Autonomous web application generation using GPT-5 + GPT-5-Codex
- **Architecture**: GPT-5 orchestration → Tool methods → GPT-5-Codex code generation
- **Key Features**: Unicode project names, modification support, Selenium debugging
- **File Location**: `~/monadic/data/auto_forge/[ProjectName]_[Timestamp]/`
- **Documentation**: `docs/apps/auto_forge.md` (public), `docs_dev/auto_forge_internals.md` (internal)

### Working with PDF Documents
- **Local Storage**: Uses PGVector for embeddings, requires PostgreSQL container
- **Cloud Storage**: Uses OpenAI Vector Store API, requires OpenAI API key
- **Endpoints**: `/pdf` (local), `/openai/pdf` (cloud)
- Session variable `pdf_storage_mode` tracks current mode

### Debugging WebSocket Issues
- Check browser console for connection errors
- Verify Ruby server logs (`rake server:debug` for verbose output)
- Ensure Docker containers are running (`docker ps`)
- Check network tab for WebSocket frames
- Enable `EXTRA_LOGGING=true` in config for detailed traces

### Updating AI Model Versions

When updating to new model versions (e.g., Claude Haiku 4.5, Veo 3.1), follow this comprehensive checklist to ensure all related files are synchronized:

#### 1. Implementation Code
- **MDSL files** (`apps/*/app_name_provider.mdsl`):
  - Update `model` parameter in `llm do` block
  - Update system prompt references to model capabilities
  - Update tool descriptions if model capabilities changed
- **Helper modules** (`lib/monadic/adapters/vendors/*_helper.rb`):
  - Update model name pattern matching (maintain backward compatibility)
  - Update any model-specific logic or parameters
- **Script files** (e.g., `scripts/generators/video_generator_veo.rb`):
  - Update model constants and default values
  - Update comments and user-facing messages

#### 2. Model Specifications
- **`public/js/monadic/model_spec.js`**:
  - Add new model entries with complete specifications
  - Include all capabilities: context_window, max_output_tokens, tool_capability, vision_capability, etc.
  - Add any new features (e.g., thinking_budget, supports_thinking)

#### 3. Tests
- **Unit tests** (`spec/unit/**/*_spec.rb`):
  - Update mock API endpoints with new model names
  - Update test expectations if model behavior changed
- **Test documentation** (`spec/**/README*.md`):
  - Update descriptions of supported models
  - Update feature lists and specifications

#### 4. Documentation (Both EN and JA)
- **User documentation** (`docs/basic-usage/basic-apps.md`, `docs/ja/basic-usage/basic-apps.md`):
  - Update model version numbers
  - Update specifications (resolution, duration, capabilities)
  - Update feature descriptions
- **Internal documentation** (`docs_dev/**/*.md`):
  - Update technical specifications
  - Update implementation notes

#### 5. Backward Compatibility
- When adding new model versions, maintain support for previous versions in pattern matching
- Example:
  ```ruby
  if vm == 'quality' || vm.include?('veo-3.1-generate-preview') || vm.include?('veo-3.0-generate-001')
    # Support both new and old model names
  end
  ```

#### 6. Verification Checklist
After updating, verify:
- [ ] All MDSL files using the provider have been updated
- [ ] Model specifications match official API documentation
- [ ] Tests pass with new model names
- [ ] Both English and Japanese documentation updated
- [ ] No hard-coded old model names remain (use grep to search)
- [ ] Backward compatibility maintained where appropriate

#### Example: Complete Model Update Flow
1. Check official provider documentation for new model specifications
2. Update `model_spec.js` with new model entry
3. Update all MDSL files that should use the new model
4. Update helper modules with new model name patterns
5. Update test mocks and expectations
6. Update both EN and JA user documentation
7. Update internal technical documentation
8. Run full test suite to verify changes
9. Check documentation with link checker

## Code Quality Guidelines

### Language Usage
- **Code and tests must be in English only** (no Japanese, Chinese, or other languages in comments, variable names, or test data)
- **Exception**: Language configuration files (`language_config.rb`) and UI translation features require native language strings - these are functionally necessary

### Formatting Standards
- Ruby: Use 2-space indentation consistently
- Avoid extra spaces in strings, arrays, and method calls
- Run linting before committing: `bundle exec rubocop`
- EditorConfig settings are provided for consistent formatting

### DOM Helpers (Frontend JavaScript)
jQuery has been completely removed. Use these global helpers defined in `dom-helpers.js`:
- `$id("elementId")` — `document.getElementById()` replacement (returns null if not found)
- `$show(el)` / `$hide(el)` — Set `style.display` to `""` / `"none"` (null-safe)
- `$toggle(el, bool)` — Show or hide based on boolean
- `$on(el, event, fn)` — `addEventListener` wrapper (null-safe)
- `$dispatch(el, eventName)` — Dispatch bubbling event (null-safe)

**Rules**: Never use `document.getElementById()` directly — always use `$id()`. Never use jQuery (`$()`, `jQuery()`). For Bootstrap modals/tooltips, use native API (`bootstrap.Modal.getOrCreateInstance()`).

### Test Directory Management
- Test artifacts are automatically created in `tmp/test_runs/`
- Directory structure is managed by `spec/support/test_run_dir.rb`
- No manual directory creation needed - handled automatically by test framework

### Provider Independence (CRITICAL)
**NEVER implement cross-provider processing:**
- Each provider version (OpenAI, Claude, Gemini, etc.) MUST use only its own API
- NEVER have one provider's class instantiate or call another provider's class
- **Example of VIOLATION:**
  ```ruby
  # WRONG: Claude version calling OpenAI version
  class ConceptVisualizerClaude < MonadicApp
    def generate_diagram(...)
      ConceptVisualizerOpenAI.new.generate_diagram(...)  # VIOLATION!
    end
  end
  ```
- **Correct approach:**
  ```ruby
  # RIGHT: Shared logic in provider-independent module
  module ConceptVisualizerTools
    def generate_diagram(...)
      # Provider-independent implementation
    end
  end

  class ConceptVisualizerOpenAI < MonadicApp
    include OpenAIHelper
    include ConceptVisualizerTools  # Uses shared tools
  end

  class ConceptVisualizerClaude < MonadicApp
    include ClaudeHelper
    include ConceptVisualizerTools  # Uses shared tools
  end
  ```
- **Why this matters:** User selects Claude to use Claude's API, not to secretly call OpenAI
- **When to use shared modules:** For tool logic that doesn't involve API calls (file operations, data processing, rendering, etc.)

### Configuration Priority (Important)
Configuration values follow this priority order (highest to lowest):
1. **Environment Variables** (`~/monadic/config/env`) - User settings, highest priority
2. **providerDefaults** (`model_spec.js`) - SSOT for per-provider default models
3. **Hardcoded Defaults** - Built-in fallback values in code

### GPT-5-Codex Integration
- **Access**: All OpenAI API key holders have access to GPT-5-Codex
- **Agent Pattern**: Main model handles user interaction, delegates complex coding to GPT-5-Codex
- **Shared Module**: Use `lib/monadic/agents/gpt5_codex_agent.rb` for GPT-5-Codex integration
- **Responses API**: Uses `/v1/responses` endpoint with adaptive reasoning
- **Message Format**: Monadic Chat uses "text" field internally, not "content"
- **Progress Updates**: WebSocket broadcasts progress every minute for long-running operations
  - Messages sent via EventMachine channel to appear in temp card UI
  - See `docs_dev/websocket_progress_broadcasting.md` for implementation details

### Model Configuration Strategy
- **providerDefaults (SSOT)**: `model_spec.js` defines `provider × category → model list`; first = default
- **MDSL Overrides**: Apps with special requirements keep explicit `model` in `.mdsl` files
- **Agents**: Reference `ModelSpec.default_code_model` / `default_vision_model` / `default_audio_model` / `default_image_model` / `default_video_model` / `default_tts_model` / `default_embedding_model` with hardcoded fallbacks
- **Intentional Flexibility**: Model name "inconsistencies" in MDSL overrides are by design for user choice
