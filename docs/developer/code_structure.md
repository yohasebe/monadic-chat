# Code Organization and File Structure

This document describes the directory and file structure of the Ruby backend code for Monadic Chat, located under `docker/services/ruby/lib/monadic`.

## Directory Layout

```text
docker/services/ruby/
├── lib/monadic/
│   ├── version.rb        # Monadic Chat version
│   ├── monadic.rb        # Main entry point and environment setup
│   ├── app.rb            # MonadicApp class and application loader
│   ├── app_extensions.rb # Monadic functionality extensions
│   ├── core.rb           # Core functional programming operations
│   ├── json_handler.rb   # JSON serialization for monadic mode
│   ├── html_renderer.rb  # HTML rendering for monadic context
│   ├── dsl.rb            # Monadic DSL loader and definitions
│   ├── agents/           # Business-logic agents
│   │   ├── ai_user_agent.rb
│   │   └── ...
│   ├── adapters/         # External integrations and helper modules
│   │   ├── bash_command_helper.rb
│   │   ├── file_analysis_helper.rb
│   │   └── ...
│   │   └── vendors/      # Third-party API clients
│   │       ├── openai_helper.rb
│   │       └── ...
│   └── utils/            # Utility functions and common code
│       ├── string_utils.rb
│       ├── interaction_utils.rb
│       └── ...
├── apps/                 # Application definitions (auto-loaded)
│   ├── chat/
│   ├── code_interpreter/
│   └── ...
├── scripts/              # Utility and diagnostic scripts
│   ├── utilities/        # Build and setup utilities
│   ├── cli_tools/        # Command-line tools
│   ├── generators/       # Content generators
│   └── diagnostics/      # Diagnostic and verification scripts
│       └── apps/         # App-specific diagnostics
└── spec/                 # RSpec unit test files
```

## Layer Descriptions

- **version.rb**: Defines the Monadic Chat version constant.
- **monadic.rb**: Loads dependencies, environment configuration, utility setup, and initializes apps.
- **app.rb**: Contains the `MonadicApp` class, responsible for loading adapters and agents, and defining core methods like `send_command` and `send_code`.
- **app_extensions.rb**: Provides monadic functionality methods (`monadic_unit`, `monadic_unwrap`, `monadic_map`, `monadic_html`) to MonadicApp.
- **core.rb**: Implements core functional programming operations (wrap, unwrap, transform, bind) for monadic mode.
- **json_handler.rb**: Handles JSON serialization/deserialization for monadic state management.
- **html_renderer.rb**: Renders monadic context as collapsible HTML sections with improved UI for empty objects.
- **dsl.rb**: Implements the Monadic DSL loader for `.rb` and `.mdsl` recipe files.
- **agents/**: Contains agent modules defining business logic behaviors.
- **adapters/**: Contains helper modules for executing commands, handling container interactions, and other integrations. Subfolder `vendors/` holds API client helpers.
- **utils/**: Contains pure utility modules such as string processing, file I/O, embeddings, and setup scripts.

By separating code into **agents**, **adapters**, and **utils**, the project maintains a clear structure that distinguishes business logic, external integrations, and shared utilities, making development and maintenance more intuitive.

## Important Notes

### App Loading
- All `.rb` and `.mdsl` files in the `docker/services/ruby/apps/` directory are automatically loaded during initialization
- Files in `test/` subdirectories within apps are ignored to prevent test scripts from being loaded as applications
- Diagnostic scripts for verifying app functionality should be placed in `docker/services/ruby/scripts/diagnostics/apps/` instead

### Scripts Organization

#### Ruby Scripts (`docker/services/ruby/scripts/`)
- **utilities/**: Scripts for building and setup tasks
- **cli_tools/**: Standalone command-line tools
- **generators/**: Scripts that generate content (images, videos, etc.)
- **diagnostics/**: Diagnostic and verification scripts organized by app

#### Python Scripts (`docker/services/python/scripts/`)
- **utilities/**: System utilities (`sysinfo.sh`, `run_jupyter.sh`)
- **cli_tools/**: CLI tools (`content_fetcher.py`, `webpage_fetcher.py`)
- **converters/**: File converters (`pdf2txt.py`, `office2txt.py`, `extract_frames.py`)
- **services/**: API services (`jupyter_controller.py`)

### Testing and Diagnostics

#### Unit Tests (RSpec)
- Located in `docker/services/ruby/spec/`
- Automated tests for Ruby code modules and helpers
- Run with `rake spec` or `bundle exec rspec`
- Follow RSpec naming convention: `*_spec.rb`

#### Diagnostic Scripts
- Located in `docker/services/ruby/scripts/diagnostics/`
- Manual verification scripts for app functionality
- Used to test content generation, API integrations, etc.
- Run individually to verify specific features work correctly

### Container Build Notes
- Script permissions are set recursively during container build using:
  ```dockerfile
  RUN find /path/to/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
  ```
- All subdirectories are added to PATH for easy script execution

### User Scripts
- Users can add custom scripts to `~/monadic/data/scripts` (host) / `/monadic/data/scripts` (container)
- These scripts are automatically made executable and added to PATH during command execution
- See [Shared Folder Documentation](../docker-integration/shared-folder.md#scripts) for details

## Reasoning Models Implementation

### Model Detection and Parameter Mapping

Monadic Chat automatically detects reasoning models and adjusts their parameters accordingly. This is implemented through pattern matching and provider-specific configurations.

#### Detection Logic

##### OpenAI Models
```ruby
# In openai_helper.rb
REASONING_MODELS = ["o3", "o4", "o1"]  # Partial string match
NON_STREAM_MODELS = ["o1-pro", "o1-pro-2025-03-19", "o3-pro"]  # Complete string match
```

##### Pattern-Based Detection
```ruby
# In second_opinion_agent.rb
reasoning_patterns = {
  "gemini" => /2\.5.*preview/i,
  "openai" => /^o[13](-|$)/i,
  "mistral" => /^magistral(-|$)/i,
}
```

#### Parameter Mapping

##### Reasoning Effort Mapping
Different providers implement `reasoning_effort` differently:

| Provider | Parameter | Implementation |
|----------|-----------|----------------|
| **OpenAI** | `reasoning_effort` | Direct API parameter |
| **Claude 4.0** | `budget_tokens` | Low: 50%, Medium: 70%, High: 80% of max_tokens |
| **Gemini 2.5** | `thinkingBudget` | Percentage-based with provider-specific minimums |
| **Mistral Magistral** | `reasoning_effort` | Direct API parameter |
| **Perplexity r1-1776** | N/A | No specific parameter |

##### Implementation Example (Claude)
```ruby
# In claude_helper.rb
if model_identifier.start_with?("claude-opus-4", "claude-sonnet-4")
  case reasoning_effort
  when "low"
    parameters["budget_tokens"] = (parameters["max_tokens"] * 0.5).to_i
  when "medium"
    parameters["budget_tokens"] = (parameters["max_tokens"] * 0.7).to_i
  when "high"
    parameters["budget_tokens"] = (parameters["max_tokens"] * 0.8).to_i
  end
  parameters.delete("temperature")
  parameters.delete("top_p")
end
```

##### Implementation Example (Gemini)
```ruby
# In gemini_helper.rb
if model.match?(/2\.5.*preview/i)
  thinking_budget = case reasoning_effort
  when "low" then flash_model ? 0.3 : 0.3
  when "medium" then flash_model ? 0.6 : 0.6
  when "high" then flash_model ? 0.8 : 0.8
  else 0.5
  end
  
  # Apply minimums based on model type
  if flash_model
    thinking_budget = [thinking_budget, 0.05].max  # 5% minimum
  else
    thinking_budget = [thinking_budget, 0.2].max   # 20% minimum
  end
end
```

### Response Processing

#### Thinking Block Removal
Some models include thinking blocks in their responses that need to be removed:

```ruby
# Mistral Magistral
response_content.gsub!(/<thinking>.*?<\/thinking>/m, "")
response_content.gsub!(/\\boxed{([^}]+)}/, '\1')

# Gemini 2.5 (handled natively by API)
# Returns thinking content separately in response["candidates"][0]["thought"]
```

### Web Search Model Switching

Reasoning models often lack native tool support, requiring automatic model switching for web search:

```ruby
# When web search is enabled with a reasoning model
if is_reasoning_model && web_search_enabled
  fallback_model = CONFIG["WEBSEARCH_MODEL"] || "gpt-4.1-mini"
  # Switch to fallback model for search, then back to reasoning model
end
```

### Streaming Support

Some reasoning models don't support streaming responses:

```ruby
NON_STREAM_MODELS = ["o1-pro", "o1-pro-2025-03-19", "o3-pro"]

# Disable streaming for these models
if NON_STREAM_MODELS.include?(model)
  parameters["stream"] = false
end
```

### Function Calling Limitations

Many reasoning models have limited or no function calling support:

```ruby
NON_TOOL_MODELS = [
  "o1", "o1-2024-12-17", "o1-mini", "o1-mini-2024-09-12",
  "o1-preview", "o1-preview-2024-09-12"
]

# Disable tools for these models
if NON_TOOL_MODELS.include?(model)
  parameters.delete("tools")
  parameters.delete("tool_choice")
end
```

### Provider-Specific Endpoints

Some providers use special endpoints for reasoning models:

```ruby
# Gemini 2.5 uses v1beta endpoint
if model.match?(/2\.5.*preview/i)
  endpoint = "v1beta/models/#{model}:generateContent"
end
```