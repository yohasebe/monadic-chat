# AutoForge / Artifact Builder

AutoForge (marketed as "Artifact Builder") is an autonomous application builder that creates complete, single-file web applications *and* command-line tools through intelligent AI orchestration.

## Overview

AutoForge uses advanced AI models for planning and orchestration, combined with provider-specific code generation models. It creates self-contained HTML applications with embedded CSS and JavaScript or standalone CLI scripts, requiring no external dependencies.

## Key Features

### 1. Intelligent Application Generation
- **Autonomous Planning**: Advanced AI models analyze requirements and create detailed implementation plans.
- **Provider-Specific Codegen**: Specialized code generation models deliver production-ready artifacts.
- **Single-File Output**: Web apps ship as a single HTML file; CLI tools ship as a standalone script.

### 2. CLI Tool Support
- **Language Detection**: AutoForge selects Python, Ruby, Node.js, or other languages based on the requested behaviour.
- **Optional Assets on Demand**: README, config templates, and dependency manifests are only suggested when a project actually benefits from them.
- **Actionable Guidance**: Post-generation instructions include permissions, execution commands, and next steps.
- **Custom Text Assets**: Provide a `file_name` and `instructions` to generate any additional Markdown, config, or documentation file you need.

### 3. Project Management
- **Automatic Organization**: Projects are saved with timestamps and descriptive names.
- **Unicode Support**: Full support for international characters in project names.
- **Modification Support**: Existing applications can be updated iteratively.
- **Project Listing**: View all previously generated projects.

### 4. Debugging with Selenium (Optional, Web Apps Only)
- **Automated Testing**: Runs applications in headless Chrome via Selenium.
- **Error Detection**: Identifies JavaScript errors and console warnings.
- **Performance Metrics**: Measures load time, DOM ready, and render time.
- **Functionality Tests**: Verifies interactive elements work correctly.

## How to Use

### Basic Workflow

1. **Start a Conversation**: Open Artifact Builder and describe what you want to build
2. **Provide Requirements**: Specify the application name, type, description, and features
3. **Generate Application**: The system will create your application automatically
4. **Debug (Optional)**: If Selenium is available, test the application for errors
5. **Modify as Needed**: Request changes to improve or add features

### Example Applications

Artifact Builder can create various types of web applications:
- Scientific calculators
- Todo list applications with local storage
- Countdown timers
- Drawing canvas applications
- Memory card games
- Form builders
- Markdown editors
- Color palette generators

Artifact Builder also supports CLI utilities such as:
- Runtime and environment inspectors
- Data conversion scripts (CSV/JSON/XML)
- Backup and archiving helpers
- Log analyzers and stream processors
- File organizers and bulk rename tools

### Tool Commands

The system provides several tools you can request:

#### `generate_application`
Creates or modifies an application based on specifications.

Example:
```json
{
  "spec": {
    "name": "TodoApp",
    "type": "productivity",
    "description": "A simple todo list manager",
    "features": ["Add tasks", "Mark complete", "Delete tasks", "Local storage"]
  }
}
```

#### `debug_application`
Tests an existing web application using Selenium (requires Selenium container).

Example:
```json
{
  "spec": {
    "name": "TodoApp"
  }
}
```

#### `list_projects`
Shows all previously generated projects with their locations and creation times.

#### `validate_specification`
Checks if your application specification is complete before generation.

#### `generate_additional_file`
Available for CLI projects. Generates optional assets when they add clear value:
- `readme` – usage instructions for the generated script.
- `config` – template config file when the tool references configuration inputs.
- `requirements` – dependency list (for example, `requirements.txt` or `Gemfile`) when non-standard libraries are detected.
- `usage_examples` – Markdown guide with real-world scenarios (automatically suggested for tools with rich flag parsing).
- **Custom file** – supply both `file_name` and `instructions` to materialize any text-based artifact (e.g., `USAGE.md`, `CHANGELOG.md`, `.env.example`).

Example (custom asset):
```json
{
  "file_name": "USAGE.md",
  "instructions": "Document three typical workflows with commands and expected output."
}
```

## Technical Details

### Architecture
- **Orchestration Layer**: GPT-5 (OpenAI), Claude Sonnet 4.5 (Claude), or Grok-4-Fast-Reasoning (xAI) handles planning, user interaction, and tool coordination via MDSL apps.
- **Code Generation Layer**: GPT-5-Codex, Claude Sonnet 4.5, or Grok-Code-Fast-1 produces the web/CLI artifact.
- **File Management**: The Ruby backend manages project storage, context persistence, and optional file generation.
- **Debug Layer**: Python/Selenium integration provides automated testing for web apps.

### File Storage
Projects are stored in `~/monadic/data/auto_forge/` with the following structure:
```
auto_forge/
├── TodoApp_20250127_143022/
│   └── index.html
├── Calculator_20250127_151234/
│   └── index.html
├── runtimes-lister_20250928_234449/
│   ├── runtimes_lister.py
│   └── README.md (optional)
└── ...
```

### Code Quality Standards
All generated applications follow these standards:
- Modern responsive design using CSS Grid/Flexbox
- Vanilla JavaScript (no external frameworks)
- Semantic HTML5 elements
- Mobile-first responsive design
- Accessibility best practices (ARIA labels)
- CSS variables for theming

## Advanced Features

### Modifying Existing Applications
To modify an existing application:
1. Use the same application name as before
2. Specify what changes you want
3. The system will find and update the most recent version

### Starting Fresh
To create a new version from scratch:
1. Use the same name but add `"reset": true` to the specification
2. This will create a new project folder with a fresh implementation

### Debugging Report
When `debug_application` is used for web apps, you receive:
- JavaScript error list
- Console warnings
- Functionality test results (forms, buttons, interactive elements)
- Performance metrics (load time, DOM ready, render time)
- Viewport information

## Requirements

### Basic Requirements
- Monadic Chat with Ruby backend
- One of the following:
  - OpenAI API key with access to GPT-5 and GPT-5-Codex
  - Anthropic API key with access to Claude Sonnet 4.5
  - xAI API key with access to Grok-4-Fast-Reasoning and Grok-Code-Fast-1

### Optional Requirements
- Docker with Selenium container for debugging features (web apps only)
- Python container for Selenium integration (for Selenium tests)

## Application Scope

1. **Single-File Applications**: Web projects are delivered as one HTML file; CLI projects as standalone scripts.
2. **Self-Contained Design**: Web apps use embedded resources instead of external CDNs. CLI tools generate dependency manifests when non-standard libraries are used.
3. **Client-Side Architecture**: Web projects run entirely in the browser without server components.
4. **Session Focus**: Each conversation focuses on one application at a time

## Best Practices

1. **Clear Requirements**: Provide detailed descriptions of desired functionality
2. **Iterative Development**: Start simple and add features progressively
3. **Test Regularly**: Use `debug_application` after generating web apps to catch issues
4. **Meaningful Names**: Use descriptive project names for easy identification

## Troubleshooting

### Common Issues

1. **Files Not Generated**: GPT-5-Codex or Claude Sonnet 4.5 can take 2-5 minutes for complex apps. Progress appears in the streaming temp card while generation runs.
2. **Selenium Not Available**: Ensure Docker Selenium container is running
3. **Unicode Characters**: Project names with special characters are fully supported
4. **Custom file requests rejected**: Make sure the filename is simple (no directories) and include clear instructions describing the desired content.

### Error Messages

- "Missing required parameters": Ensure all specification fields are provided
- "Selenium container is not running": Enable Selenium in Monadic Chat settings
- "Project not found": Check the exact project name with list_projects

## Provider Support & Progress Updates

AutoForge supports multiple providers:
- **OpenAI Auto Forge**: GPT-5 orchestrates the workflow while GPT-5-Codex handles code generation.
- **Claude Auto Forge**: Claude Sonnet 4.5 orchestrates and generates code via the Claude Responses API.
- **Grok Auto Forge**: Grok-4-Fast-Reasoning orchestrates the workflow while Grok-Code-Fast-1 handles code generation.

All variants broadcast long-running progress updates to the streaming temp card so you can track generation without monitoring the status bar.

### Grok-Specific Characteristics

Grok-Code-Fast-1 excels at:
- **Fast Iteration**: Quick generation with 92 tokens/sec throughput
- **Front-End Development**: HTML/CSS/JavaScript, SVG graphics, animations
- **Modern CSS**: Grid, Flexbox, CSS variables
- **Cost Efficiency**: 6-7x cheaper than GPT-5-Codex

Grok-Code-Fast-1 is optimized for:
- Smaller, focused tasks with iterative development
- Visual components and simple animations
- Vanilla JavaScript implementations
- Self-contained single-file applications
