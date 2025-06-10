---
sidebar_label: Code Organization
---

# Code Organization and File Structure

This document describes the directory and file structure of the Ruby backend code for Monadic Chat, located under `docker/services/ruby/lib/monadic`.

## Directory Layout

```text
docker/services/ruby/
├── lib/monadic/
│   ├── version.rb        # Monadic Chat version
│   ├── monadic.rb        # Main entry point and environment setup
│   ├── app.rb            # MonadicApp class and application loader
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
│   └── diagnostics/      # Test and diagnostic scripts
│       └── apps/         # App-specific tests
└── spec/                 # RSpec test files
```

## Layer Descriptions

- **version.rb**: Defines the Monadic Chat version constant.
- **monadic.rb**: Loads dependencies, environment configuration, utility setup, and initializes apps.
- **app.rb**: Contains the `MonadicApp` class, responsible for loading adapters and agents, and defining core methods like `send_command` and `send_code`.
- **dsl.rb**: Implements the Monadic DSL loader for `.rb` and `.mdsl` recipe files.
- **agents/**: Contains agent modules defining business logic behaviors.
- **adapters/**: Contains helper modules for executing commands, handling container interactions, and other integrations. Subfolder `vendors/` holds API client helpers.
- **utils/**: Contains pure utility modules such as string processing, file I/O, embeddings, and setup scripts.

By separating code into **agents**, **adapters**, and **utils**, the project maintains a clear structure that distinguishes business logic, external integrations, and shared utilities, making development and maintenance more intuitive.

## Important Notes

### App Loading
- All `.rb` and `.mdsl` files in the `apps/` directory are automatically loaded during initialization
- Files in `test/` subdirectories within apps are ignored to prevent test scripts from being loaded as applications
- Test scripts should be placed in `scripts/diagnostics/apps/` instead

### Scripts Organization
- **utilities/**: Scripts for building and setup tasks
- **cli_tools/**: Standalone command-line tools (formerly `simple_*.rb`)
- **generators/**: Scripts that generate content (images, videos, etc.)
- **diagnostics/**: Test and diagnostic scripts organized by app