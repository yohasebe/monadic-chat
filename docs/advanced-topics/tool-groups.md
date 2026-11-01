# Tool Groups

## Overview

Tool groups are sets of related tools that several apps share. An app imports a group with `import_shared_tools`, and the app's description shows which groups it uses.

## Tool Group Badges

The app's description area shows the tool groups as badges, in up to three rows:

- **Tools (Always)**: groups whose tools are sent to the model from the start
- **Tools (Conditional)**: groups that stay hidden until the model asks for them with `request_tool`
- **Capabilities**: features of the app, such as web search or the Knowledge Base

Each badge has the group's icon and name. Hover over a badge to see its description and the number of tools. A conditional group whose requirements are not met is not shown.

## Available Tool Groups

The lists of apps below name the built-in apps that import each group.

### Groups Without Requirements

#### Jupyter Operations (12 tools)
- Create and manage Jupyter notebooks
- Add cells to notebooks
- Execute code in JupyterLab
- List and retrieve notebook contents

**Apps using this**: Jupyter Notebook

#### Python Execution (4 tools)
- Execute Python code in the Python container
- Check the Python environment and packages
- Install Python libraries

**Apps using this**: Code Interpreter, Jupyter Notebook, Math Tutor, Research Assistant

#### File Operations (3 tools)
- Read files from the shared folder
- Write or append to files in the shared folder
- List files in the shared folder

**Apps using this**: Every app gets this group automatically.

#### File Reading (3 tools)
- Read text files from the shared folder
- Extract text from PDF files
- Extract text from Office documents (Word, Excel, PowerPoint)

**Apps using this**: Code Interpreter, Jupyter Notebook, Math Tutor, Research Assistant

#### Planning (1 tool)
- Propose a plan for a task with several steps
- The plan is shown to the user for approval before the work starts

**Apps using this**: Most apps that use tools, for example Code Interpreter, Coding Assistant, Research Assistant, Jupyter Notebook, Math Tutor, AutoForge (OpenAI, Grok), Mermaid Grapher, DrawIO Grapher and Web Insight

#### Parallel Python Execution (1 tool)
- Execute 2-5 independent Python code snippets in parallel
- Each snippet runs in its own process, and the results are collected together
- Progress is shown in the temporary card while it runs

**Apps using this**: Code Interpreter

#### Parallel Dispatch (1 tool)
- Dispatch 2-5 independent sub-tasks to run in parallel as separate API calls
- Each sub-agent runs as a text-only call; the results are collected and combined
- Sub-agents can search the web when the Web Search toggle is on. The search uses the provider's own search, or the Tavily API for providers without it; see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities)
- Progress is shown in the temporary card while it runs

**Apps using this**: Research Assistant

#### Verification (1 tool)
- Record the result of checking the work before presenting it to the user
- Statuses: passed, issues found, fixed
- The tool loop stops when the status is passed or fixed, or after 3 attempts
- The status is shown in the temporary card while it runs

**Apps using this**: Code Interpreter, Jupyter Notebook, Mermaid Grapher, AutoForge (OpenAI, Grok)

#### App Creation (3 tools)
- List the Monadic Chat apps
- Get detailed information about an app
- Create a basic app template file

**Apps using this**: No built-in app; custom apps can use it through `import_shared_tools` or `reachable_skills`

#### Session Context (4 tools)
- Get, update, and clear the conversation context (topics, people, notes)
- Remove specific items from the context
- The context is shown in the sidebar panel

**Apps using this**: Chat Plus

### Groups With Requirements

#### Web Automation (16 tools)
**Requires**: the Selenium and Python containers

- Capture web pages as viewport-sized screenshots (with device presets)
- Run an interactive browser session visible through noVNC
- Navigate, click, type, scroll, select, and press keys in the interactive browser
- Inspect the page structure and mark candidate elements

**Apps using this**: Web Insight, AutoForge, Research Assistant (OpenAI, Claude, Gemini, Grok)

The Selenium container starts with Monadic Chat. If the group is not shown, wait for startup to finish; if the Selenium image is missing, run **Actions → Build All** to download it.

#### Video Analysis (1 tool)
**Requires**: an app on OpenAI, Anthropic, Gemini, or xAI, with that provider's API key

- Analyze video content with a multimodal model
- Describe the video from its frames
- Frames are sent only to the app's own provider. The audio track is transcribed when that provider offers speech-to-text (OpenAI, Gemini, xAI); otherwise the description says that the audio was not transcribed

**Apps using this**: Video Describer

#### Web Search (4 tools)
**Requires**: `TAVILY_API_KEY`

- Search the web and fetch pages through Tavily, with citations
- Fetch the content of a URL and save it to the shared folder

The search tools of this group return results through Tavily. A provider's own web search is a separate feature, turned on with the Web Search toggle, and works without this group; see the [Provider Capabilities table](../basic-usage/basic-apps.md#provider-capabilities). Without `TAVILY_API_KEY`, the search tools of this group return no results.

**Apps using this**: Research Assistant, Mermaid Grapher, Wikipedia

#### Audio Transcription (1 tool)
**Requires**: an app on OpenAI, Gemini, or xAI, with that provider's API key

- Transcribe audio files with speech-to-text
- The audio is sent only to the app's own provider; apps on other providers do not offer this tool

**Apps using this**: Speech Draft Helper

#### Image Analysis (1 tool)
**Requires**: an app on OpenAI, Anthropic, Gemini, xAI, Mistral, Cohere, or DeepSeek, with that provider's API key

- Describe the contents of an image file with the model's vision capability
- The image is sent only to the app's own provider

**Apps using this**: Code Interpreter, Research Assistant, Speech Draft Helper

#### Library Search (1 tool)
**Requires**: the Knowledge Base (Qdrant and embeddings containers)

- Search the Knowledge Base for passages relevant to a query
- Returns passages with citations that link back to the conversation or document

**Apps using this**: Added to the apps that can search the Knowledge Base; used when the Knowledge Base retrieval switch is on for the session

Groups that need a capability the provider lacks (image, video or audio input) are not added to apps on that provider.

## Understanding Tool Availability

### Why Some Tools Are Unavailable

1. **Containers**: Some tools need Docker containers (Selenium, Python)
2. **API keys**: Some tools need a specific API key
3. **Provider capabilities**: Some tools need image, video or audio input

### Error Messages

When a tool cannot run, the error message says what is missing (for example, "Selenium container is not running") and how to fix it (for example, wait for the container to start, or run **Actions → Build All** if the Selenium image is missing).

## Creating Apps with Tool Groups

In your own MDSL apps, you can import tool groups instead of defining each tool. See [Monadic DSL](monadic_dsl.md).

### Example

```ruby
app "MyCustomAppOpenAI" do
  llm do
    provider "openai"
    model "<model-id>"
  end

  # Import Python execution tools
  import_shared_tools :python_execution, visibility: "always"

  # Import web automation tools (hidden until the model asks for them)
  import_shared_tools :web_automation, visibility: "conditional"
end
```

The default visibility is `"conditional"`.

## Dynamic Skills (reachable_skills)

An app does not have to declare every tool it might use. With `reachable_skills`, an app declares tool groups it may acquire during a conversation. The tools stay hidden until the model needs them.

How it works:

1. The hidden groups are shown to the model as a short menu (each group's name and a one-line description).
2. When the model needs a group, it asks for it by name (`request_tool("web_search_tools")`).
3. The whole group is unlocked, and its tools can be used for the rest of the conversation.

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

`reachable_skills :group_a, :group_b` is the same as importing each group with `import_shared_tools :group_a, visibility: "conditional"`. `reachable_skills :safe` expands to the read-only groups: Web Search, File Reading, Image Analysis, Video Analysis, Audio Transcription, Session Context, Verification and Planning.

Acquired skills are kept when a session is exported and restored when it is imported, so a saved conversation resumes with the same tools.

## Troubleshooting

### Tool Group Remains Unavailable

If a tool group stays unavailable after the containers it needs have started:

1. **Reload the web interface**: availability is checked when the app list is built
2. **Restart Monadic Chat**: Stop, then Start
3. **Check the containers**: run `docker ps`, or read the messages in the console panel
4. **Check the logs**: container logs may show why a container did not start

### Tools Not Working as Expected

If tools are available but do not work:

1. **Check the shared folder**: make sure the files can be read
2. **Check the API keys**: make sure they are valid and have credit
3. **Check the container logs**: look for errors in the container output
4. **Restart Monadic Chat**

## Related Documentation

- [Monadic DSL](monadic_dsl.md) - Creating custom apps
- [Docker Integration](../docker-integration/basic-architecture.md) - Container management
- [Shared Folder](../docker-integration/shared-folder.md) - File operations
