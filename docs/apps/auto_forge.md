# AutoForge / Artifact Builder

AutoForge (marketed as "Artifact Builder") is an autonomous application builder that creates complete, single-file web applications through intelligent AI orchestration.

## Overview

AutoForge uses GPT-5 for planning and orchestration, combined with GPT-5-Codex for high-quality code generation. It creates self-contained HTML applications with embedded CSS and JavaScript, requiring no external dependencies.

## Key Features

### 1. Intelligent Application Generation
- **Autonomous Planning**: GPT-5 analyzes requirements and creates detailed implementation plans
- **Production-Ready Code**: GPT-5-Codex generates complete, working applications
- **Single-File Output**: All code is contained in one HTML file for easy deployment

### 2. Project Management
- **Automatic Organization**: Projects are saved with timestamps and descriptive names
- **Unicode Support**: Full support for international characters in project names
- **Modification Support**: Existing applications can be updated iteratively
- **Project Listing**: View all previously generated projects

### 3. Debugging with Selenium (Optional)
- **Automated Testing**: Runs applications in headless Chrome via Selenium
- **Error Detection**: Identifies JavaScript errors and console warnings
- **Performance Metrics**: Measures load time, DOM ready, and render time
- **Functionality Tests**: Verifies interactive elements work correctly

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
Tests an existing application using Selenium (requires Selenium container).

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

## Technical Details

### Architecture
- **Orchestration Layer**: GPT-5 handles planning, user interaction, and tool coordination
- **Code Generation Layer**: GPT-5-Codex generates the actual HTML/CSS/JavaScript code
- **File Management**: Ruby backend manages project storage and retrieval
- **Debug Layer**: Python/Selenium integration for automated testing

### File Storage
Projects are stored in `~/monadic/data/auto_forge/` with the following structure:
```
auto_forge/
├── TodoApp_20250127_143022/
│   └── index.html
├── Calculator_20250127_151234/
│   └── index.html
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
When debug_application is used, you receive:
- JavaScript error list
- Console warnings
- Functionality test results (forms, buttons, interactive elements)
- Performance metrics (load time, DOM ready, render time)
- Viewport information

## Requirements

### Basic Requirements
- Monadic Chat with Ruby backend
- OpenAI API key with access to GPT-5 and GPT-5-Codex

### Optional Requirements
- Docker with Selenium container for debugging features
- Python container for Selenium integration

## Limitations

1. **Single-File Applications**: All code must fit in one HTML file
2. **No External Dependencies**: Cannot use external libraries or frameworks
3. **Client-Side Only**: No server-side functionality
4. **One App Per Session**: Focus on one application per conversation

## Best Practices

1. **Clear Requirements**: Provide detailed descriptions of desired functionality
2. **Iterative Development**: Start simple and add features progressively
3. **Test Regularly**: Use debug_application after generation to catch issues
4. **Meaningful Names**: Use descriptive project names for easy identification

## Troubleshooting

### Common Issues

1. **Files Not Generated**: GPT-5-Codex can take 2-5 minutes for complex apps
2. **Selenium Not Available**: Ensure Docker Selenium container is running
3. **Unicode Characters**: Project names with special characters are fully supported

### Error Messages

- "Missing required parameters": Ensure all specification fields are provided
- "Selenium container is not running": Enable Selenium in Monadic Chat settings
- "Project not found": Check the exact project name with list_projects

## Model Selection

AutoForge supports multiple models:
- **GPT-5**: Recommended for optimal orchestration
- **GPT-5-Codex**: Available for both orchestration and code generation
- **GPT-4.1**: Fallback option for basic functionality

Note: GPT-5 and GPT-5-Codex use the Responses API, which may have different performance characteristics than standard models.