# Tool Groups

## Overview

Tool groups are collections of related tools that can be shared across multiple applications. When you create or use an app, you'll see badges indicating which tool groups are available.

## Tool Group Badges

Tool group badges appear in the app selector interface and indicate which tools are available:

- **Blue badges** (🔧): Always-available tools (e.g., File Operations, Python Execution)
- **Yellow badges** (⚡): Conditionally-available tools (e.g., Web Automation - requires Selenium)

The badge shows both the tool group name and the number of tools in that group.

## Available Tool Groups

### Always Available

These tool groups are always available and don't require additional setup:

#### Jupyter Operations (12 tools)
- Create and manage Jupyter notebooks
- Add cells to notebooks
- Execute code in JupyterLab
- List and retrieve notebook contents

**Apps using this**: Jupyter Notebook (all providers)

#### Python Execution (4 tools)
- Execute Python code in a sandboxed container
- Check Python environment and packages
- Access computational libraries (NumPy, Pandas, etc.)

**Apps using this**: Code Interpreter, Jupyter Notebook

#### File Operations (3 tools)
- Write files to shared folder
- List files in shared folder
- Delete files from shared folder

**Apps using this**: Chat Plus, Code Interpreter, Jupyter Notebook

#### File Reading (3 tools)
- Read text files from shared folder
- Extract text from PDF files
- Extract text from Office documents (Word, Excel, PowerPoint)

**Apps using this**: Research Assistant, Content Reader, Chat Plus

#### Planning (1 tool)
- Propose structured execution plans for complex multi-step tasks
- AI presents plan to user for approval before executing

**Apps using this**: All tool-enabled apps (Code Interpreter, Research Assistant, Coding Assistant, Jupyter Notebook, AutoForge, Math Tutor, etc.)

#### Parallel Python Execution (1 tool)
- Execute 2-5 independent Python code snippets in parallel
- Each snippet runs in its own process with results collected together
- Progress displayed in real-time via the temporary card UI
- Ideal for simultaneous visualizations, statistical analyses, and model comparisons

**Apps using this**: Code Interpreter (all providers)

#### Parallel Dispatch (1 tool)
- Dispatch 2-5 independent sub-tasks to run in parallel via separate API calls
- Each sub-agent runs as a text-only call; results are collected and synthesized
- Supports **web search** for sub-agents when the Web Search toggle is enabled in the UI
- Web search uses provider-native mechanisms (OpenAI/Grok Responses API, Gemini grounding, Claude server-side search) or Tavily API as a fallback for providers without native search (Mistral, Cohere, DeepSeek)
- Progress displayed in real-time via the temporary card UI

**Apps using this**: Research Assistant (all providers)

#### Verification (1 tool)
- Record the outcome of self-verifying work before presenting it to the user
- Supports statuses: passed, issues found, fixed
- Automatically stops the tool loop when verification passes or the retry limit (3 attempts) is reached
- Verification status is displayed in the temporary card UI during processing

**Apps using this**: Code Interpreter, Jupyter Notebook, AutoForge, Mermaid Grapher, Chord Accompanist (all providers)

### Conditionally Available

These tool groups require specific containers or API keys to be available:

#### Web Automation (4 tools)
**Requires**: Selenium container running

- Capture viewport-sized screenshots of web pages
- Capture full-page screenshots
- Debug web applications with automated testing
- Scrape web content

**Apps using this**: Visual Web Explorer (all providers), AutoForge (all providers)

**How to enable**:
1. Go to **Actions** menu
2. Select **Start Selenium Container**
3. Wait for the container to start
4. The tool group badge will change from unavailable to available

#### Video Analysis (1 tool)
**Requires**: OpenAI API key configured

- Analyze video content using multimodal AI
- Generate descriptions from video frames

**Apps using this**: Video Describer

**How to enable**:
1. Configure your OpenAI API key in Settings
2. The tool group will become available automatically

## Understanding Tool Availability

### Why Some Tools Are Unavailable

Tools may be unavailable for several reasons:

1. **Missing Containers**: Some tools require Docker containers (Selenium, Python) to be running
2. **Missing API Keys**: Some tools require specific API keys to be configured
3. **System Requirements**: Some tools may require specific system resources or dependencies

### Error Messages

When you try to use an unavailable tool, you'll receive a clear error message explaining:
- What is missing (e.g., "Selenium container is not running")
- How to fix it (e.g., "Start the Selenium container from Actions menu")

## Creating Apps with Tool Groups

If you're creating custom apps using MDSL, you can import tool groups instead of defining tools individually. See the [Monadic DSL documentation](monadic_dsl.md) for details.

### Example

```ruby
MonadicApp.register "MyCustomApp" do
  llm do
    provider "openai"
    model "<model-id>"
  end

  # Import file operations tools
  import_shared_tools :file_operations, visibility: "always"

  # Import web automation tools (conditional on Selenium)
  import_shared_tools :web_automation, visibility: "conditional"
end
```

## Benefits of Tool Groups

1. **Consistency**: Tools work the same way across all apps
2. **Clarity**: Clear indication of which features require additional setup
3. **Error Prevention**: Unavailable tools are hidden or show helpful error messages
4. **Efficiency**: Tool groups are reused across apps, reducing code duplication

## Troubleshooting

### Tool Group Remains Unavailable

If a tool group shows as unavailable even after starting the required containers:

1. **Refresh the app list**: The UI checks availability every 10 seconds
2. **Restart containers**: Stop and start the container from the Actions menu
3. **Check container status**: Use `Actions → Show Container Status` to verify containers are running
4. **Check logs**: Container logs may show errors preventing startup

### Tools Not Working as Expected

If tools are available but not working correctly:

1. **Check shared folder permissions**: Ensure files are accessible
2. **Check API keys**: Verify API keys are valid and have sufficient credits
3. **Check container logs**: Look for errors in container output
4. **Restart the app**: Some issues may be resolved by restarting Monadic Chat

## Related Documentation

- [Monadic DSL](monadic_dsl.md) - Creating custom apps
- [Docker Integration](../docker-integration/basic-architecture.md) - Container management
- [Shared Folder](../docker-integration/shared-folder.md) - File operations
