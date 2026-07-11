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
- Read files from shared folder
- Write or append to files in shared folder
- List files in shared folder

**Apps using this**: Chat Plus, Code Interpreter, Jupyter Notebook

#### File Reading (3 tools)
- Read text files from shared folder
- Extract text from PDF files
- Extract text from Office documents (Word, Excel, PowerPoint)

**Apps using this**: Research Assistant, Chat Plus

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
- Web search uses the provider's native mechanism, or the Tavily API for providers without native search — see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities)
- Progress displayed in real-time via the temporary card UI

**Apps using this**: Research Assistant (all providers)

#### Verification (1 tool)
- Record the outcome of self-verifying work before presenting it to the user
- Supports statuses: passed, issues found, fixed
- Automatically stops the tool loop when verification passes or the retry limit (3 attempts) is reached
- Verification status is displayed in the temporary card UI during processing

**Apps using this**: Code Interpreter, Jupyter Notebook, AutoForge, Mermaid Grapher, DrawIO Grapher, Second Opinion (all providers)

#### App Creation (3 tools)
- List all available Monadic Chat applications
- Get detailed information about a specific app
- Create a basic app template file

**Apps using this**: Not imported by built-in apps by default; available to custom apps via `import_shared_tools` or `reachable_skills`

#### Session Context (4 tools)
- Get, update, and clear conversation context (topics, people, notes)
- Remove specific items from context
- Context is displayed in the sidebar panel

**Apps using this**: Chat Plus (all providers)

### Conditionally Available

These tool groups require specific containers or API keys to be available:

#### Web Automation (16 tools)
**Requires**: Selenium and Python containers running

- Capture web pages as viewport-sized screenshots (with device presets)
- Run an interactive browser session visible via noVNC
- Navigate, click, type, scroll, select, and press keys in the interactive browser
- Inspect page structure and annotate candidate elements for disambiguation

**Apps using this**: Web Insight (all providers), AutoForge (all providers)

**How to enable**:
The Selenium container starts automatically with Monadic Chat. If the badge
shows the group as unavailable, wait for startup to finish; if the Selenium
image is missing, run **Actions → Build All** to download it.

#### Video Analysis (1 tool)
**Requires**: At least one vision-capable provider API key (OpenAI, Anthropic, Gemini, or xAI)

- Analyze video content using multimodal AI
- Generate descriptions from video frames

**Apps using this**: Video Describer

**How to enable**:
1. Configure at least one of the supported API keys (OpenAI, Anthropic, Gemini, or xAI) in Settings
2. The tool group will become available automatically

#### Web Search (4 tools)
**Requires**: `TAVILY_API_KEY` for providers without native web search — see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities)

- Search the web using the provider-appropriate method (native or Tavily)
- Fetch content from URLs and save it to the shared folder
- Tavily-backed search and page fetch with citations

**Apps using this**: Research Assistant, Mermaid Grapher, Wikipedia

#### Audio Transcription (1 tool)
**Requires**: OpenAI or Gemini API key configured

- Transcribe audio files using speech-to-text capabilities

**Apps using this**: Video Describer, Speech Draft Helper

#### Image Analysis (1 tool)
**Requires**: At least one vision-capable provider API key (OpenAI, Anthropic, Gemini, or xAI)

- Analyze and describe the contents of an image file using vision capabilities

**Apps using this**: Code Interpreter, Research Assistant (all providers)

#### Library Search (1 tool)
**Requires**: Knowledge Base (embeddings service) available

- Search the project-wide Knowledge Base for passages relevant to a query
- Returns snippets with citations linking back to the original conversation or document

**Apps using this**: Automatically injected into eligible apps; the tool is additionally gated by the per-session Knowledge Base retrieval toggle

## Understanding Tool Availability

### Why Some Tools Are Unavailable

Tools may be unavailable for several reasons:

1. **Missing Containers**: Some tools require Docker containers (Selenium, Python) to be running
2. **Missing API Keys**: Some tools require specific API keys to be configured
3. **System Requirements**: Some tools may require specific system resources or dependencies

### Error Messages

When you try to use an unavailable tool, you'll receive a clear error message explaining:
- What is missing (e.g., "Selenium container is not running")
- How to fix it (e.g., wait for container startup to finish, or run **Actions → Build All** if the Selenium image is missing)

## Creating Apps with Tool Groups

If you're creating custom apps using MDSL, you can import tool groups instead of defining tools individually. See the [Monadic DSL documentation](monadic_dsl.md) for details.

### Example

```ruby
app "MyCustomAppOpenAI" do
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

## Dynamic Skills (reachable_skills)

An app does not have to declare every tool it might ever use. With `reachable_skills`, an app can declare tool groups it is *allowed to acquire on demand* during a conversation. The tools stay hidden until the model actually needs them.

How it works:

1. The hidden groups are presented to the model as a short menu (each group's name and a one-line description).
2. When the model decides it needs a group, it requests it by name (`request_tool("web_search_tools")`).
3. The whole group is unlocked and its tools become usable within the same conversation.

```ruby
app "MyAssistantOpenAI" do
  llm do
    provider "openai"
    model "<model-id>"
  end

  # Groups the app can reach for when the conversation calls for them.
  reachable_skills :web_search_tools, :image_analysis

  # Or reach for the curated pool of read-only safe groups in one line:
  # reachable_skills :safe
end
```

`reachable_skills :group_a, :group_b` is equivalent to importing each group with `import_shared_tools :group_a, visibility: "conditional"`, but states the intent more clearly. `reachable_skills :safe` expands to the curated set of read-only safe groups.

This keeps an app lean by default: only the groups the conversation actually needs are exposed, rather than presenting every tool up front. Acquired skills are preserved when a session is exported and restored when it is reopened, so a saved conversation resumes with the same tools available.

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
3. **Check container status**: Verify containers are running with `docker ps` (or the status messages in the console panel)
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
