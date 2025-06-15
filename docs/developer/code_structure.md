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
│   ├── agents/           # Business-logic agents (formerly helpers/agents)
│   │   ├── ai_user_agent.rb
│   │   └── ...
│   ├── adapters/         # External integrations and helper modules (formerly helpers)
│   │   ├── bash_command_helper.rb
│   │   ├── file_analysis_helper.rb
│   │   └── ...
│   │   └── vendors/      # Third-party API clients (formerly helpers/vendors)
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