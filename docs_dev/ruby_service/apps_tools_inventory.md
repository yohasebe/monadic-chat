# Monadic Chat Apps - Tools Inventory

## Overview

This document provides a comprehensive inventory of shared tool groups and custom tools across all Monadic Chat applications. The system uses a Progressive Tool Disclosure (PTD) architecture where tools are organized into named groups with visibility settings.

## Shared Tool Groups (System-wide)

These tool groups are defined centrally in `/docker/services/ruby/lib/monadic/shared_tools/registry.rb` and can be imported by any app.

### 1. file_operations
**Module:** `MonadicSharedTools::FileOperations`
**Default Visibility:** Always
**Description:** Read, write, and list files in the shared folder

**Tools:**
- `read_file_from_shared_folder` - Read a file from shared folder and return its content with metadata
- `write_file_to_shared_folder` - Write or append content to a file (supports Unicode and subdirectories)
- `list_files_in_shared_folder` - List all files and directories in a folder or subdirectory

**Default PTD Hint:** "Call request_tool(\"file_operations\") when you need to read, write, or list files in the shared folder."

---

### 2. python_execution
**Module:** `MonadicSharedTools::PythonExecution`
**Default Visibility:** Always
**Description:** Execute Python, Ruby, Shell, and other code

**Tools:**
- `run_code` - Execute program code and return the output
- `run_bash_command` - Execute a bash command in the Python container
- `check_environment` - Check the Python container environment
- `lib_installer` - Install a library using package manager (pip, uv, or apt)

**Default PTD Hint:** "Call request_tool(\"python_execution\") when you need to run Python code, execute bash commands, or inspect the execution environment."

---

### 3. file_reading
**Module:** `MonadicSharedTools::FileReading`
**Default Visibility:** Always
**Description:** Read text from various file types

**Tools:**
- `fetch_text_from_file` - Read text content from files (txt, code, data files, etc.)
- `fetch_text_from_pdf` - Extract text content from a PDF file with full-page support
- `fetch_text_from_office` - Extract text from Office files (docx, xlsx, pptx)

**Default PTD Hint:** "Call request_tool(\"file_reading\") when you need to read text from files, PDFs, or Office documents."

---

### 4. web_search_tools
**Module:** `MonadicSharedTools::WebSearchTools`
**Default Visibility:** Conditional (available when web search is enabled)
**Description:** Search the web and fetch content from URLs

**Tools:**
- `search_web` - Search the web using provider-appropriate search method (native or Tavily)
- `fetch_web_content` - Fetch content from a URL and save to shared folder
- `tavily_search` - Perform a Tavily web search (requires TAVILY_API_KEY)
- `tavily_fetch` - Fetch full content from a URL using Tavily API

**Default PTD Hint:** "Call request_tool(\"web_search_tools\") when you need to search the web or fetch content from URLs."

---

### 5. web_automation
**Module:** `MonadicSharedTools::WebAutomation`
**Default Visibility:** Conditional (available when Selenium is running)
**Description:** Capture and interact with web pages using Selenium

**Tools:**
- `capture_viewport_screenshots` - Capture a web page as multiple viewport-sized screenshots
- `list_captured_screenshots` - List all screenshots captured in current session
- `get_viewport_presets` - Get available viewport preset dimensions
- `capture_webpage_text` - Extract text content from a web page in Markdown format
- `debug_application` - Debug a generated web application using Selenium

**Default PTD Hint:** "Call request_tool(\"web_automation\") when you need to capture web pages as screenshots, extract webpage text, or debug web applications using Selenium."

---

### 6. content_analysis_openai
**Module:** `MonadicSharedTools::ContentAnalysisOpenAI`
**Default Visibility:** Conditional (available when OpenAI API is configured)
**Description:** Analyze video, image, and audio content using OpenAI's multimodal capabilities

**Tools:**
- `analyze_video` - Analyze video and generate description (image recognition + audio transcription)
- `analyze_image` - Analyze and describe image contents using OpenAI vision
- `analyze_audio` - Analyze and transcribe audio using OpenAI's Whisper

**Default PTD Hint:** "Call request_tool(\"content_analysis_openai\") when you need to analyze video, image, or audio content using OpenAI's multimodal capabilities."

---

### 7. jupyter_operations
**Module:** `MonadicSharedTools::JupyterOperations`
**Default Visibility:** Always
**Description:** Create, manage, and execute Jupyter notebooks

**Tools:**
- `run_jupyter` - Start or stop JupyterLab server
- `create_jupyter_notebook` - Create a new Jupyter notebook with automatic timestamping
- `add_jupyter_cells` - Add and optionally execute cells
- `delete_jupyter_cell` - Delete a cell by index
- `update_jupyter_cell` - Update the content of an existing cell
- `get_jupyter_cells_with_results` - Get all cells with execution results
- `execute_and_fix_jupyter_cells` - Execute cells with automatic error detection
- `list_jupyter_notebooks` - List all notebooks in data directory
- `restart_jupyter_kernel` - Restart kernel and clear outputs
- `interrupt_jupyter_execution` - Interrupt running cells
- `move_jupyter_cell` - Move a cell to a new position
- `insert_jupyter_cells` - Insert cells at a specific position

**Default PTD Hint:** "Call request_tool(\"jupyter_operations\") when you need to create, manage, or execute Jupyter notebooks."

---

### 8. app_creation
**Module:** `MonadicSharedTools::AppCreation`
**Default Visibility:** Always
**Description:** List and create Monadic Chat applications

**Tools:**
- `list_monadic_apps` - List all available Monadic Chat applications
- `get_app_info` - Get detailed information about a specific app
- `create_simple_app_template` - Create a basic app template file

**Default PTD Hint:** "Call request_tool(\"app_creation\") when you need to list, inspect, or create Monadic Chat applications."

---

## App-by-App Tools Inventory

### Auto Forge (3 providers: Claude, Grok, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:web_automation [conditional]` |
| **Custom Tools** | • `generate_application` - Generate a complete application<br/>• `validate_specification` - Validate app specification<br/>• `list_projects` - List previously generated projects<br/>• `generate_additional_file` - Generate additional project files |

---

### Chat (9 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, Ollama, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |
| **Notes** | Basic conversational AI with no special tools |

---

### Chat Plus (9 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, Ollama, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools** | (none) |

---

### Chord Accompanist (1 provider: Claude)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `validate_chord_progression` - Validate chord progression for music theory<br/>• `validate_abc_syntax` - Validate ABC notation syntax using abcjs<br/>• `analyze_abc_error` - Analyze ABC syntax errors and suggest fixes |

---

### Code Interpreter (7 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:python_execution [always]`<br/>`:file_reading [always]` |
| **Custom Tools (OpenAI only)** | • `gpt5_codex_agent` - Delegate complex Python tasks to GPT-5-Codex |
| **Custom Tools (Grok only)** | • `grok_code_agent` - Call Grok-Code-Fast-1 for complex tasks |

---

### Coding Assistant (8 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools (OpenAI only)** | • `gpt5_codex_agent` - Delegate complex tasks to GPT-5-Codex |
| **Custom Tools (Grok only)** | • `grok_code_agent` - Call Grok-Code-Fast-1 for complex tasks |

---

### Concept Visualizer (2 providers: Claude, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `generate_concept_diagram` - Generate conceptual diagram using LaTeX/TikZ<br/>• `list_diagram_examples` - Show diagram type examples |

---

### Content Reader (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]`<br/>`:web_search_tools [conditional]`<br/>`:content_analysis_openai [conditional]` |
| **Custom Tools** | • `fetch_text_from_pdf` - Extract text from PDF<br/>• `fetch_text_from_office` - Extract from Office files<br/>• `fetch_text_from_file` - Read text from file |

---

### Document Generator (1 provider: Claude)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools** | (none) |

---

### Draw.io Grapher (2 providers: Claude, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `write_drawio_file` - Save Draw.io diagram to file |

---

### Image Generator (3 providers: Gemini, Grok, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `generate_image_with_gemini` - Generate/edit using Google's models<br/>• `generate_image_with_openai` - Generate using OpenAI<br/>• `generate_image_with_grok` - Generate using Grok/DALL-E 3 |

---

### Jupyter Notebook (4 providers: Claude, Gemini, Grok, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:jupyter_operations [always]`<br/>`:python_execution [always]`<br/>`:file_operations [always]`<br/>`:file_reading [always]` |
| **Custom Tools (OpenAI only)** | • `gpt5_codex_agent` - Delegate complex notebook tasks to GPT-5-Codex |
| **Custom Tools (Gemini/Grok)** | • `create_and_populate_jupyter_notebook` - Create notebook with cells in one operation |

---

### Language Practice (8 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |

---

### Language Practice Plus (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |

---

### Mail Composer (8 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools** | (none) |

---

### Math Tutor (4 providers: Claude, Gemini, Grok, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:python_execution [always]`<br/>`:file_reading [always]` |
| **Custom Tools** | (none) |

---

### Mermaid Grapher (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:web_search_tools [conditional]` |
| **Custom Tools** | • `validate_mermaid_syntax` - Validate diagram syntax<br/>• `analyze_mermaid_error` - Analyze errors and suggest fixes<br/>• `preview_mermaid` - Save preview image<br/>• `fetch_mermaid_docs` - Get documentation URL |

---

### Monadic Help (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `find_help_topics` - Search documentation with multiple context chunks<br/>• `get_help_document` - Retrieve full document by ID<br/>• `list_help_sections` - List all doc sections<br/>• `search_help_by_section` - Search within specific section |

---

### Novel Writer (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools** | • `count_num_of_words` - Count word count<br/>• `count_num_of_chars` - Count character count |

---

### PDF Navigator (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `find_closest_text` - Find closest text via embedding similarity<br/>• `get_text_snippet` - Retrieve text snippet from DB<br/>• `list_titles` - List doc IDs and titles<br/>• `find_closest_doc` - Find closest doc via embedding<br/>• `get_text_snippets` - Retrieve all snippets for a doc |

---

### Research Assistant (7 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]`<br/>`:web_search_tools [conditional]` |
| **Custom Tools (OpenAI only)** | • `request_tool` - Request access to locked tool<br/>• `gpt5_codex_agent` - Delegate code generation to GPT-5-Codex |
| **Custom Tools (Grok only)** | • `request_tool` - Request access to locked tool<br/>• `grok_code_agent` - Call Grok-Code-Fast-1 for code generation |

---

### Second Opinion (9 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, Ollama, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `second_opinion_agent` - Verify response before returning to user |

---

### Speech Draft Helper (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]`<br/>`:content_analysis_openai [conditional]` |
| **Custom Tools** | • `fetch_text_from_file` - Fetch text from file<br/>• `fetch_text_from_pdf` - Extract from PDF<br/>• `fetch_text_from_office` - Extract from Office files<br/>• `list_providers_and_voices` - List TTS providers and voices<br/>• `text_to_speech` - Convert text to speech MP3 |

---

### Syntax Tree (2 providers: Claude, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:file_operations [always]` |
| **Custom Tools** | • `render_syntax_tree` - Render syntax tree as SVG using LaTeX |

---

### Translate (2 providers: Cohere, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |

---

### Video Describer (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:content_analysis_openai [conditional]` |
| **Custom Tools** | (none) |

---

### Video Generator (2 providers: Gemini, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | • `generate_video_with_veo` - Generate videos using Veo 3.1 (Gemini)<br/>• `generate_video_with_sora` - Generate videos using Sora 2 (OpenAI) |

---

### Visual Web Explorer (4 providers: Claude, Gemini, Grok, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:web_automation [conditional]` |
| **Custom Tools** | (none) |

---

### Voice Chat (8 providers: Claude, Cohere, DeepSeek, Gemini, Grok, Mistral, OpenAI, Perplexity)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |

---

### Voice Interpreter (2 providers: Cohere, OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | (none) |
| **Custom Tools** | (none) |

---

### Wikipedia (1 provider: OpenAI)

| Field | Details |
|-------|---------|
| **Imported Tools** | `:web_search_tools [conditional]` |
| **Custom Tools** | • `search_wikipedia` - Search Wikipedia articles via Wikimedia API |

---

## Summary Statistics

### By Shared Tool Group (Usage)

| Shared Tool Group | Apps Using | Count |
|-------------------|------------|-------|
| `:file_operations` | Chat Plus, Coding Assistant, Content Reader, Document Generator, Jupyter Notebook, Mail Composer, Novel Writer, Research Assistant, Speech Draft Helper, Syntax Tree | 10 |
| `:web_search_tools` | Content Reader, Mermaid Grapher, Research Assistant, Wikipedia | 4 |
| `:python_execution` | Code Interpreter, Jupyter Notebook, Math Tutor | 3 |
| `:file_reading` | Code Interpreter, Jupyter Notebook, Math Tutor | 3 |
| `:jupyter_operations` | Jupyter Notebook | 1 |
| `:content_analysis_openai` | Content Reader, Speech Draft Helper, Video Describer | 3 |
| `:web_automation` | Auto Forge, Visual Web Explorer | 2 |

### By Visibility Setting

| Visibility | Tool Groups | Count |
|------------|------------|-------|
| **Always** | file_operations, python_execution, file_reading, jupyter_operations, app_creation | 5 |
| **Conditional** | web_search_tools, web_automation, content_analysis_openai | 3 |

### Apps with Most Tool Imports

1. **Jupyter Notebook** - 4 shared tool groups (jupyter_operations, python_execution, file_operations, file_reading)
2. **Content Reader** - 3 shared tool groups (file_operations, web_search_tools, content_analysis_openai)
3. Multiple apps - 2 shared tool groups (Auto Forge, Chat Plus, Coding Assistant, etc.)

### Provider-Specific Custom Tools

- **OpenAI**: gpt5_codex_agent (Code Interpreter, Coding Assistant, Jupyter Notebook, Research Assistant)
- **Grok**: grok_code_agent (Code Interpreter, Coding Assistant, Jupyter Notebook, Research Assistant)
- **All Providers**: second_opinion_agent (Second Opinion app, 9 variants)

### Apps with No Tools

- Chat (all 9 variants)
- Language Practice (all 8 variants)
- Language Practice Plus
- Translate (Cohere, OpenAI variants)
- Voice Chat (all 8 variants)
- Voice Interpreter (Cohere, OpenAI variants)

---

## Key Architecture Patterns

### 1. Progressive Tool Disclosure (PTD)
Tools are marked as "always" or "conditional" visibility:
- **Always**: Available immediately (file operations, python execution, etc.)
- **Conditional**: Unlocked via `request_tool()` when needed (web search, web automation, etc.)

### 2. Provider-Specific Variants
Some apps have provider-specific custom tools:
- **GPT-5-Codex delegation** (OpenAI): gpt5_codex_agent
- **Grok-Code integration** (Grok): grok_code_agent
- **Specialized operations** (Gemini): create_and_populate_jupyter_notebook

### 3. Multi-Tool Composition
Complex apps import multiple tool groups:
- **Jupyter Notebook**: 4 groups - full environment for notebook development
- **Content Reader**: 3 groups - content analysis and file handling
- **Research Assistant**: 2 groups - file and web integration

### 4. Tool Sharing Across Apps
Common tool groups reduce duplication:
- `:file_operations` used by 10 apps
- `:web_search_tools` used by 4 apps for research capabilities

---

## Implementation Files

### Shared Tools Modules
Located in `/docker/services/ruby/lib/monadic/shared_tools/`:
- `registry.rb` - Central registry with all tool definitions
- `file_operations.rb` - File I/O implementation
- `python_execution.rb` - Code execution
- `file_reading.rb` - File parsing (PDF, Office, text)
- `web_search_tools.rb` - Web search integration
- `web_automation.rb` - Selenium-based web interaction
- `content_analysis_openai.rb` - Multimodal content analysis
- `jupyter_operations.rb` - Notebook management
- `app_creation.rb` - App introspection and creation

### App-Specific Tools
Located in `/docker/services/ruby/apps/{app_name}/`:
- `{app_name}_tools.rb` - Custom tool implementations for the app
- `{app_name}_{provider}.mdsl` - MDSL definitions importing and defining tools

