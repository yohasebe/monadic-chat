# Tool Analysis Report: Non-Grouped Tools in Monadic Chat

## Executive Summary

**Total Unique Tools Found: 66**
- Existing Grouped Tools: 3 (file_reading actually exists in multiple apps)
- Tools in 5 Existing Groups: 15
- **Ungrouped Tools: 51**

This analysis identifies tools NOT in the following 5 existing shared tool groups:
1. **file_operations**: read_file_from_shared_folder, write_file_to_shared_folder, list_files_in_shared_folder
2. **python_execution**: run_code, run_bash_command, check_environment, lib_installer
3. **web_tools**: search_web, fetch_web_content
4. **app_creation**: list_monadic_apps, get_app_info, create_simple_app_template
5. **file_reading**: fetch_text_from_file, fetch_text_from_pdf, fetch_text_from_office

---

## MAJOR SHARED TOOL GROUPS (Candidates for New Grouping)

### 1. JUPYTER NOTEBOOK OPERATIONS (19 tools, 4 apps)
**Apps Using**: jupyter_notebook (4 instances: openai, grok, claude, gemini)
**Functional Area**: Complete Jupyter notebook lifecycle management

#### High-Frequency Tools (4 uses each):
- `run_jupyter`: Start/stop JupyterLab
- `create_jupyter_notebook`: Create new notebook
- `add_jupyter_cells`: Add and run cells (array of cell objects)
- `delete_jupyter_cell`: Delete by index
- `update_jupyter_cell`: Update cell content and type
- `get_jupyter_cells_with_results`: Retrieve cells with execution results
- `execute_and_fix_jupyter_cells`: Execute and error reporting
- `list_jupyter_notebooks`: List available notebooks
- `restart_jupyter_kernel`: Restart kernel and clear outputs
- `interrupt_jupyter_execution`: Stop running cells

#### Medium-Frequency Tools (2-3 uses):
- `move_jupyter_cell`: Reorganize cells (from_index, to_index)
- `insert_jupyter_cells`: Insert cells at position (index, cells)
- `create_and_populate_jupyter_notebook`: Single operation (USE THIS FOR CREATING)
- `restart_jupyter_kernel`: Alternative form

#### Parameter Patterns:
- **filename**: string (notebook.ipynb)
- **cells**: array of {cell_type, source, ...}
- **index**: integer (0-based)
- **content**: string
- **cell_type**: "code" or "markdown"
- **command**: "start" or "stop"
- **run**: boolean
- **escaped**: boolean
- **from_index/to_index**: integers

**Grouping Recommendation**: YES - Create `jupyter_operations` shared tool group
**Shared Implementation**: MonadicHelper provides JupyterAPI wrapper, tools are consistent across providers

---

### 2. VISUAL WEB EXPLORATION TOOLS (4 tools, 4 apps)
**Apps Using**: visual_web_explorer (claude, openai, gemini, grok)
**Functional Area**: Web scraping and screenshot capture

#### Tools (all 4 uses):
- `capture_viewport_screenshots`: Capture multi-viewport screenshots
- `list_captured_screenshots`: List captured screenshots in session
- `get_viewport_presets`: Get available viewport dimensions
- `capture_webpage_text`: Extract text in Markdown format

#### Parameter Patterns:
- **url**: string
- **viewport_width/height**: integer (default 1920x1080)
- **overlap**: integer (pixels, default 100)
- **preset**: string ("desktop", "tablet", "mobile", "print")

**Grouping Recommendation**: YES - Create `web_exploration` or `screenshot_tools` shared tool group
**Implementation Note**: Uses Selenium backend for rendering

---

### 3. AUTO FORGE / APPLICATION GENERATION (5 tools, 3 apps)
**Apps Using**: auto_forge (claude, openai, grok)
**Functional Area**: Autonomous web application generation and debugging

#### Tools:
- `generate_application` (3 uses): Generate complete app from specs
- `validate_specification` (3 uses): Validate app specification
- `list_projects` (3 uses): List previously generated projects
- `debug_application` (3 uses): Debug using Selenium
- `generate_additional_file` (3 uses): Generate README, config, dependencies

#### Parameter Patterns:
- **specification**: string or object (app design/requirements)
- **project_name**: string
- **selenium_debugging**: boolean
- **file_type**: string (README, config, requirements)
- **language**: string (for generation context)

**Grouping Recommendation**: YES - Create `app_generation` shared tool group
**Note**: Provider-specific implementations (claude_helper, openai_helper, etc.)

---

### 4. RESEARCH ASSISTANT / INFORMATION GATHERING (6 tools, 4 apps)
**Apps Using**: research_assistant (openai, cohere, deepseek, mistral, grok, claude, gemini) + mermaid_grapher
**Functional Area**: Web search and information retrieval

#### High-Frequency Tools:
- `tavily_search` (3 uses): Tavily web search with summaries + citations
- `tavily_fetch` (3 uses): Fetch full URL content from search results
- `websearch_agent` (2 uses): Grok's live search + web search (mermaid_grapher)
- `request_tool` (2 uses): Request access to locked tools

#### Parameter Patterns:
- **query**: string
- **url**: string
- **max_results**: integer
- **include_images**: boolean
- **tool_name**: string (for request_tool)
- **request_reason**: string

**Grouping Recommendation**: PARTIAL - Some tools are provider-specific
- tavily_search/tavily_fetch: Universal, can be shared
- websearch_agent: Provider-specific (Grok native, mermaid_grapher uses search)
- request_tool: Research-assistant specific (tool request/unlock system)

---

### 5. AGENT DELEGATION TOOLS (2 tools, 6 apps)
**Apps Using**: code_interpreter, coding_assistant, jupyter_notebook, research_assistant (openai versions)
**Functional Area**: Complex task delegation to specialized LLM agents

#### Tools:
- `gpt5_codex_agent` (6 uses): Delegate complex coding to GPT-5-Codex
- `grok_code_agent` (6 uses): Delegate to Grok-Code-Fast-1

#### Parameter Patterns:
- **task_description**: string
- **context**: object (code context)
- **requirements**: array
- **code_language**: string
- **error_info**: string (when fixing errors)

**Grouping Recommendation**: PARTIAL - Provider-specific
- These are delegation patterns to provider-specific agents
- Could be grouped as `agent_delegation` with provider parameter

---

### 6. IMAGE GENERATION/MANIPULATION (3 tools, 3 apps)
**Apps Using**: image_generator (openai, grok, gemini)
**Functional Area**: Multi-provider image generation

#### Tools (all 3 uses):
- `generate_image_with_openai`: DALL-E 3 image generation
- `generate_image_with_gemini`: Google AI Gemini image generation
- `generate_image_with_grok`: xAI Grok image generation

#### Parameter Patterns:
- **prompt**: string (description)
- **size**: string ("1024x1024", "1792x1024", etc.)
- **style**: string (e.g., "natural", "vivid")
- **quality**: string ("standard", "hd")
- **n**: integer (number of images)
- **edit_instructions**: string (for edits)

**Grouping Recommendation**: YES - Create `image_generation` shared tool group
**Note**: Each tool is provider-specific but consistent structure
**Use Case**: image_generator app offers multi-provider selection

---

### 7. VIDEO GENERATION (2 tools, 1 app)
**Apps Using**: video_generator (openai, gemini)
**Functional Area**: AI video generation

#### Tools:
- `generate_video_with_sora` (1 use): OpenAI Sora 2 videos
- `generate_video_with_veo` (1 use): Google Veo 3.1 videos

#### Parameter Patterns:
- **prompt**: string
- **duration**: integer (seconds)
- **resolution**: string ("720p", "1080p")
- **aspect_ratio**: string ("16:9", "1:1")
- **model**: string (veo-3.1-fast-generate-preview, etc.)
- **quality**: string ("fast", "quality")

**Grouping Recommendation**: YES - Create `video_generation` shared tool group
**Implementation**: Could be merged with image_generation as `media_generation`

---

### 8. CONTENT ANALYSIS TOOLS (4-5 tools, 3 apps)
**Apps Using**: content_reader, speech_draft_helper, video_describer
**Functional Area**: Media file analysis and transcription

#### Tools:
- `analyze_image` (2 uses): Describe image contents
- `analyze_audio` (2 uses): Transcribe audio
- `analyze_video` (1 use): Generate video description
- `analyze_abc_error` (1 use): ABC music notation error analysis
- `analyze_mermaid_error` (1 use): Mermaid diagram error analysis

#### Parameter Patterns:
- **file_path**: string
- **format**: string
- **detailed**: boolean
- **include_timestamps**: boolean (audio)
- **language**: string (transcription language)

**Grouping Recommendation**: PARTIAL
- analyze_image, analyze_audio: General content analysis
- analyze_video: Media-specific (video_describer)
- analyze_abc_error, analyze_mermaid_error: Format-specific analysis tools

---

### 9. DOCUMENTATION/HELP SEARCH TOOLS (4 tools, 1 app)
**Apps Using**: monadic_help
**Functional Area**: Internal documentation search and retrieval

#### Tools (all 1 use):
- `find_help_topics`: Search documentation with chunks
- `get_help_document`: Retrieve by ID
- `list_help_sections`: List available sections
- `search_help_by_section`: Section-specific search

#### Parameter Patterns:
- **query**: string
- **section**: string
- **num_chunks**: integer (default 3)
- **doc_id**: string
- **include_subsections**: boolean

**Grouping Recommendation**: YES - Create `documentation_search` shared tool group
**Implementation**: Vector database search (PGVector)
**Reusability**: Could be adapted for other apps needing doc search

---

### 10. DIAGRAM/VISUALIZATION TOOLS (5+ tools, 3 apps)
**Apps Using**: mermaid_grapher, drawio_grapher, concept_visualizer, syntax_tree
**Functional Area**: Diagram creation and rendering

#### Tools:
- **Mermaid-specific** (5 tools, mermaid_grapher):
  - `validate_mermaid_syntax`: Validate diagram syntax
  - `analyze_mermaid_error`: Error analysis
  - `preview_mermaid`: Save preview image
  - `fetch_mermaid_docs`: Get documentation
  - `websearch_agent`: Search Mermaid syntax examples (shared with research_assistant)

- **Draw.io-specific** (1 tool, 2 apps):
  - `write_drawio_file`: Save diagram to XML file

- **LaTeX/TikZ-specific** (1 tool, 2 apps):
  - `generate_concept_diagram`: Generate LaTeX/TikZ diagrams

- **Syntax Tree-specific** (1 tool, 2 apps):
  - `render_syntax_tree`: LaTeX rendering of syntax trees

#### Parameter Patterns:
- **diagram_syntax**: string (Mermaid DSL)
- **diagram_type**: string (flowchart, sequence, gantt, etc.)
- **output_format**: string (svg, png)
- **filename**: string
- **content**: string (LaTeX/XML)

**Grouping Recommendation**: PARTIAL
- Mermaid: YES - Create `mermaid_tools` group
- Draw.io: Specific to drawio_grapher
- LaTeX/TikZ: Specific to concept_visualizer
- Syntax Tree: Specific to syntax_tree
- Could create umbrella `diagram_generation` group

---

### 11. PDF NAVIGATION TOOLS (4 tools, 1 app)
**Apps Using**: pdf_navigator
**Functional Area**: PDF document search and retrieval

#### Tools (all 1 use):
- `find_closest_doc`: Find document by semantic similarity
- `find_closest_text`: Find text by semantic search
- `get_text_snippet`: Retrieve specific text snippet
- `get_text_snippets`: Retrieve multiple snippets
- `list_titles`: List document titles

#### Parameter Patterns:
- **query**: string
- **doc_id**: string
- **snippet_id**: string
- **limit**: integer
- **similarity_threshold**: float

**Grouping Recommendation**: YES - Create `pdf_navigation` or `document_search` shared tool group
**Implementation**: Vector database (PGVector) with embeddings
**Note**: Related to file_reading but focused on semantic search

---

### 12. TEXT-TO-SPEECH TOOLS (1 tool, 1 app)
**Apps Using**: speech_draft_helper
**Functional Area**: Voice generation

#### Tools:
- `text_to_speech`: Generate MP3 from text
- `list_providers_and_voices`: List available voices

#### Parameter Patterns:
- **text**: string
- **provider_id**: string
- **voice_id**: string
- **speed**: float (0.5-2.0)
- **output_format**: string

**Grouping Recommendation**: YES - Create `text_to_speech` shared tool group
**Scope**: Could be expanded to include STT (speech-to-text) if implemented

---

### 13. CHARACTER COUNT TOOLS (2 tools, 1 app)
**Apps Using**: novel_writer
**Functional Area**: Text statistics

#### Tools:
- `count_num_of_words`: Count words
- `count_num_of_chars`: Count characters

#### Parameter Patterns:
- **text**: string
- **include_spaces**: boolean
- **exclude_markup**: boolean

**Grouping Recommendation**: PARTIAL
- Too simple for separate group
- Could be part of general `text_utilities` group
- Or combined with other text processing tools if created

---

## SINGLE-APP TOOLS (Not Grouping Candidates)

### Tools used by only ONE application:

1. **second_opinion_agent** (9 uses, second_opinion app)
   - Verify response before returning to user
   - Specific to second_opinion app pattern

2. **request_tool** (2 uses, research_assistant)
   - Request access to locked tools
   - Research-assistant specific permission system

3. **search_wikipedia** (1 use, wikipedia)
   - Wikipedia search via Wikimedia API
   - Specialized tool for wikipedia app

4. **Music Theory Tools** (chord_accompanist):
   - `validate_chord_progression`: Music theory validation
   - `validate_abc_syntax`: ABC notation validation
   - `analyze_abc_error`: ABC error analysis
   - Highly specialized for music apps

---

## RECOMMENDED NEW SHARED TOOL GROUPS

### Priority 1: HIGH IMPACT (Used by 3+ apps)

1. **jupyter_operations** (19 tools, 4 apps)
   - Impact: Simplifies notebook integration across providers
   - Consistency: All tools follow same patterns
   - Reusability: 100% shareable

2. **web_exploration** (4 tools, 4 apps)
   - Impact: Screenshot/scraping for any app needing visual web data
   - Consistency: Uniform parameters and behavior
   - Reusability: 100% shareable

3. **image_generation** (3 tools, 3 apps)
   - Impact: Multi-provider image generation on demand
   - Consistency: Similar interface across providers
   - Reusability: Other apps could use for illustrations

4. **video_generation** (2 tools, 1 app, but extensible)
   - Impact: Future-proof for video-enabled apps
   - Consistency: Can absorb new providers
   - Reusability: Support for multiple platforms

### Priority 2: MEDIUM IMPACT (Used by 2-3 apps)

5. **agent_delegation** (2 tools, 6 apps)
   - gpt5_codex_agent, grok_code_agent
   - Could add anthropic_agent, other_ai_agent
   - Impact: Unified agent invocation pattern

6. **web_search_tools** (2-3 tools)
   - tavily_search, tavily_fetch, websearch_agent
   - Impact: Research and information gathering
   - Note: websearch_agent is provider-specific

7. **diagram_generation** (4-5 tools, 3+ apps)
   - mermaid_tools, drawio_tools, concept_visualization, syntax_tree
   - Could be umbrella for visualization

### Priority 3: LOWER IMPACT but VALUABLE

8. **documentation_search** (4 tools, 1 app but reusable)
   - find_help_topics, get_help_document, etc.
   - Reusable for any app with searchable docs

9. **pdf_navigation** (4 tools, 1 app)
   - Vector search in PDFs
   - Could be extended for document processing

10. **content_analysis** (2-3 tools, 2+ apps)
    - analyze_image, analyze_audio
    - Could include analyze_video

11. **text_to_speech** (2 tools, 1 app)
    - text_to_speech, list_providers_and_voices
    - Extend with STT when available

---

## DETAILED TOOL INVENTORY TABLE

| Tool Name | Frequency | Apps | Primary Group | Provider-Specific | Grouping Candidate |
|-----------|-----------|------|---------------|------------------|--------------------|
| second_opinion_agent | 9 | 1 | Agent Pattern | No | N/A - App-specific |
| gpt5_codex_agent | 6 | 4 | Code Delegation | Yes (OpenAI) | agent_delegation |
| grok_code_agent | 6 | 4 | Code Delegation | Yes (Grok) | agent_delegation |
| run_jupyter | 4 | 1 | Jupyter | No | jupyter_operations |
| create_jupyter_notebook | 4 | 1 | Jupyter | No | jupyter_operations |
| add_jupyter_cells | 4 | 1 | Jupyter | No | jupyter_operations |
| delete_jupyter_cell | 4 | 1 | Jupyter | No | jupyter_operations |
| update_jupyter_cell | 4 | 1 | Jupyter | No | jupyter_operations |
| get_jupyter_cells_with_results | 4 | 1 | Jupyter | No | jupyter_operations |
| execute_and_fix_jupyter_cells | 4 | 1 | Jupyter | No | jupyter_operations |
| list_jupyter_notebooks | 4 | 1 | Jupyter | No | jupyter_operations |
| restart_jupyter_kernel | 4 | 1 | Jupyter | No | jupyter_operations |
| interrupt_jupyter_execution | 4 | 1 | Jupyter | No | jupyter_operations |
| capture_viewport_screenshots | 4 | 1 | Web Explorer | No | web_exploration |
| capture_webpage_text | 4 | 1 | Web Explorer | No | web_exploration |
| get_viewport_presets | 4 | 1 | Web Explorer | No | web_exploration |
| list_captured_screenshots | 4 | 1 | Web Explorer | No | web_exploration |
| validate_specification | 3 | 1 | App Generation | No | app_generation |
| tavily_search | 3 | 2 | Web Search | No | web_search_tools |
| tavily_fetch | 3 | 2 | Web Search | No | web_search_tools |
| restart_jupyter_kernel | 3 | 1 | Jupyter | No | jupyter_operations |
| move_jupyter_cell | 3 | 1 | Jupyter | No | jupyter_operations |
| list_projects | 3 | 1 | App Generation | No | app_generation |
| interrupt_jupyter_execution | 3 | 1 | Jupyter | No | jupyter_operations |
| insert_jupyter_cells | 3 | 1 | Jupyter | No | jupyter_operations |
| generate_image_with_openai | 3 | 1 | Image Gen | Yes | image_generation |
| generate_image_with_grok | 3 | 1 | Image Gen | Yes | image_generation |
| generate_image_with_gemini | 3 | 1 | Image Gen | Yes | image_generation |
| generate_application | 3 | 1 | App Generation | No | app_generation |
| generate_additional_file | 3 | 1 | App Generation | No | app_generation |
| debug_application | 3 | 1 | App Generation | No | app_generation |
| write_drawio_file | 2 | 1 | Diagram | No | diagram_generation |
| websearch_agent | 2 | 2 | Web Search | Yes | web_search_tools |
| request_tool | 2 | 1 | Research Control | No | N/A - App-specific |
| render_syntax_tree | 2 | 1 | Diagram | No | diagram_generation |
| list_diagram_examples | 2 | 1 | Diagram | No | diagram_generation |
| get_text_snippet | 2 | 1 | PDF Nav | No | pdf_navigation |
| generate_concept_diagram | 2 | 1 | Diagram | No | diagram_generation |
| find_closest_text | 2 | 1 | PDF Nav | No | pdf_navigation |
| create_and_populate_jupyter_notebook | 2 | 1 | Jupyter | No | jupyter_operations |
| analyze_image | 2 | 2 | Content Analysis | No | content_analysis |
| analyze_audio | 2 | 2 | Content Analysis | No | content_analysis |
| validate_mermaid_syntax | 1 | 1 | Mermaid | No | mermaid_tools |
| validate_chord_progression | 1 | 1 | Music Theory | No | N/A - App-specific |
| validate_abc_syntax | 1 | 1 | Music Theory | No | N/A - App-specific |
| text_to_speech | 1 | 1 | TTS | No | text_to_speech |
| search_wikipedia | 1 | 1 | Wikipedia | No | N/A - App-specific |
| search_help_by_section | 1 | 1 | Help/Docs | No | documentation_search |
| preview_mermaid | 1 | 1 | Mermaid | No | mermaid_tools |
| list_titles | 1 | 1 | PDF Nav | No | pdf_navigation |
| list_providers_and_voices | 1 | 1 | TTS | No | text_to_speech |
| list_help_sections | 1 | 1 | Help/Docs | No | documentation_search |
| get_text_snippets | 1 | 1 | PDF Nav | No | pdf_navigation |
| get_help_document | 1 | 1 | Help/Docs | No | documentation_search |
| generate_video_with_veo | 1 | 1 | Video Gen | Yes | video_generation |
| generate_video_with_sora | 1 | 1 | Video Gen | Yes | video_generation |
| find_help_topics | 1 | 1 | Help/Docs | No | documentation_search |
| find_closest_doc | 1 | 1 | PDF Nav | No | pdf_navigation |
| fetch_mermaid_docs | 1 | 1 | Mermaid | No | mermaid_tools |
| count_num_of_words | 1 | 1 | Text Stats | No | N/A - App-specific |
| count_num_of_chars | 1 | 1 | Text Stats | No | N/A - App-specific |
| analyze_video | 1 | 1 | Content Analysis | No | content_analysis |
| analyze_mermaid_error | 1 | 1 | Mermaid | No | mermaid_tools |
| analyze_abc_error | 1 | 1 | Music Theory | No | N/A - App-specific |

---

## IMPLEMENTATION RECOMMENDATIONS

### Phase 1: Create 3 High-Impact Groups
1. `jupyter_operations` - 19 tools
2. `web_exploration` - 4 tools  
3. `image_generation` - 3 tools

### Phase 2: Create 3 Medium-Impact Groups
4. `agent_delegation` - 2 tools (extensible)
5. `web_search_tools` - 2-3 tools (tavily + websearch)
6. `video_generation` - 2 tools (extensible)

### Phase 3: Create Lower-Impact but Valuable Groups
7. `diagram_generation` - 4+ tools (mermaid, drawio, concept, syntax_tree)
8. `documentation_search` - 4 tools
9. `pdf_navigation` - 4 tools
10. `content_analysis` - 3 tools
11. `text_to_speech` - 2 tools

### Phase 4: Keep App-Specific
- `second_opinion_agent`
- `request_tool`
- `validate_chord_progression`, `validate_abc_syntax`, `analyze_abc_error`
- `search_wikipedia`
- `count_num_of_words`, `count_num_of_chars`

