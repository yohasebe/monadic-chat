# Apps and Tools Inventory

This page lists the shared tool groups and the tools each built-in app declares in its MDSL files (`docker/services/ruby/apps/*/*.mdsl`). How hidden tools are unlocked is described in [progressive_tool_disclosure.md](progressive_tool_disclosure.md).

## Shared Tool Groups

Defined in `MonadicSharedTools::Registry::TOOL_GROUPS` (`lib/monadic/shared_tools/registry.rb`); the methods are in `lib/monadic/shared_tools/<group>.rb`. "UI availability" is the registry's `available_when` check, used for the badges only.

| Group | Tools | UI availability |
|---|---|---|
| `file_operations` | `read_file_from_shared_folder`, `write_file_to_shared_folder`, `list_files_in_shared_folder` | — |
| `file_reading` | `fetch_text_from_file`, `fetch_text_from_pdf`, `fetch_text_from_office` | — |
| `python_execution` | `run_code`, `run_bash_command`, `check_environment`, `lib_installer` | — |
| `parallel_python_execution` | `parallel_run_code` | — |
| `parallel_dispatch` | `dispatch_parallel_tasks` | — |
| `jupyter_operations` | `run_jupyter`, `create_jupyter_notebook`, `add_jupyter_cells`, `insert_jupyter_cells`, `update_jupyter_cell`, `delete_jupyter_cell`, `move_jupyter_cell`, `get_jupyter_cells_with_results`, `execute_and_fix_jupyter_cells`, `list_jupyter_notebooks`, `restart_jupyter_kernel`, `interrupt_jupyter_execution` | — |
| `web_search_tools` | `search_web`, `fetch_web_content`, `tavily_search`, `tavily_fetch` | `TAVILY_API_KEY` set |
| `web_automation` | `capture_viewport_screenshots`, `list_captured_screenshots`, `get_viewport_presets`, `start_browser`, `browser_navigate`, `browser_click`, `browser_type`, `browser_screenshot`, `browser_get_page_info`, `annotate_elements`, `browser_scroll`, `browser_press_key`, `browser_select`, `browser_back`, `browser_forward`, `stop_browser` | Selenium and Python containers running |
| `image_analysis` | `analyze_image` | a key of OpenAI, Anthropic, Gemini, xAI, Mistral, Cohere or DeepSeek set |
| `audio_transcription` | `analyze_audio` | a key of OpenAI, Gemini or xAI set |
| `video_analysis` | `analyze_video` | a key of OpenAI, Anthropic, Gemini or xAI set |
| `library_search` | `library_search` | embeddings service healthy |
| `session_context` | `get_context`, `update_context`, `remove_from_context`, `clear_context` | — |
| `app_creation` | `list_monadic_apps`, `get_app_info`, `create_simple_app_template` | — |
| `planning` | `propose_plan` | — |
| `verification` | `report_verification` | — |

`image_analysis`, `video_analysis` and `audio_transcription` are imported only for providers that can do the analysis themselves; otherwise the import is skipped.

## Tools Added to Every App

- `file_operations` (always visible) is added to every app that does not import it.
- `library_search` (conditional) is added to apps whose `library_search` capability is on (`finalize_capabilities!` in `dsl.rb`; off in Privacy Filter apps).
- `request_tool` is added to any app with a conditional import.

These are not repeated in the table below.

## Apps

Groups without a note are always visible. A provider list after a group or tool means only those variants declare it.

| App | Providers | Imported groups | App tools |
|---|---|---|---|
| Auto Forge | OpenAI, Claude, Grok | `web_automation` (conditional), `planning` (OpenAI, Grok only), `verification` (OpenAI, Grok only) | `generate_application`, `validate_specification`, `list_projects`, `generate_additional_file`, `claude_code_agent` (Claude), `debug_application`, `finish_task`, `grok_code_agent` (Grok), `openai_code_agent` (OpenAI) |
| Chat | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | — | — |
| Chat Plus | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek | `session_context`, `file_operations` | — |
| Code Interpreter | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek | `python_execution`, `file_reading`, `planning`, `verification`, `parallel_python_execution`, `image_analysis` (conditional) | `grok_code_agent` (Grok), `openai_code_agent` (OpenAI) |
| Coding Assistant | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | `file_operations`, `planning` | `grok_code_agent` (Grok), `openai_code_agent` (OpenAI) |
| Concept Visualizer | OpenAI, Claude | `planning` | `generate_concept_diagram`, `list_diagram_examples` |
| Document Generator | Claude | `planning`, `file_operations` | — |
| DrawIO Grapher | OpenAI, Claude, Gemini, Grok | `planning` | `preview_drawio`, `write_drawio_file`, `stop_drawio_browser` |
| Image Generator | OpenAI, Gemini, Grok | `planning` | `generate_image_with_gemini` (Gemini), `monadic_load_state`, `generate_image_with_grok` (Grok), `generate_image_with_openai` (OpenAI) |
| Jupyter Notebook | OpenAI, Claude, Gemini, Grok | `jupyter_operations`, `python_execution`, `file_operations`, `file_reading`, `planning`, `verification` | `monadic_load_state`, `create_and_populate_jupyter_notebook` (Gemini, Grok), `grok_code_agent` (Grok), `openai_code_agent` (OpenAI) |
| Knowledge Base | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | — | `list_conversations`, `search_library`, `get_conversation_details`, `library_stats`, `update_conversation_scope`, `delete_conversation_from_library`, `import_conversation_from_text` |
| Language Practice | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | — | — |
| Language Practice Plus | OpenAI, Claude | — | `load_context`, `save_response`, `set_target_language` |
| Live Conversation | OpenAI, Gemini, Grok | — | — |
| Mail Composer | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | `file_operations` | — |
| Math Tutor | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek | `python_execution`, `file_reading`, `planning` | `load_learning_progress`, `save_learning_progress`, `add_solved_problem`, `add_concepts`, `add_weak_areas`, `add_learning_notes` |
| Mermaid Grapher | OpenAI, Claude, Gemini, Grok | `web_search_tools` (conditional), `planning`, `verification` | `validate_mermaid_syntax`, `preview_mermaid`, `stop_mermaid_browser`, `analyze_mermaid_error`, `fetch_mermaid_docs` |
| Monadic Chat Help | OpenAI | — | `find_help_topics`, `get_help_document`, `list_help_sections`, `search_help_by_section` |
| Music Analyst | Gemini | — | `analyze_audio_features`, `critique_audio` |
| Music Generator | Gemini | `planning` | `generate_music_with_lyria`, `generate_music_with_elevenlabs` |
| Music Lab | OpenAI, Claude, Gemini, Grok | — | `play_chord`, `play_scale`, `play_interval`, `play_progression`, `generate_backing_track`, `analyze_audio_file` |
| Novel Writer | OpenAI, Mistral, DeepSeek | `file_operations`, `planning` | `count_num_of_words`, `count_num_of_chars`, `load_novel_context`, `save_novel_context`, `add_character`, `update_progress`, `update_summary` |
| Research Assistant | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek | `file_operations`, `python_execution`, `file_reading`, `planning`, `parallel_dispatch`, `web_search_tools` (conditional) (OpenAI, Claude, Grok, Mistral, Cohere, DeepSeek only), `web_automation` (conditional) (OpenAI, Claude, Gemini, Grok only), `image_analysis` (conditional) | `load_research_progress` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `save_research_progress` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `add_finding` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `add_research_topics` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `add_search` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `add_sources` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `add_research_notes` (OpenAI, Claude, Gemini, Grok, Mistral, Cohere), `grok_code_agent` (Grok), `openai_code_agent` (OpenAI) |
| Second Opinion | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek | — | `second_opinion_agent`, `parallel_second_opinions` |
| Speech Draft Helper | OpenAI | `file_operations`, `audio_transcription` (conditional), `image_analysis` (conditional) | `fetch_text_from_file`, `fetch_text_from_pdf`, `fetch_text_from_office`, `list_providers_and_voices`, `text_to_speech` |
| Syntax Tree | OpenAI, Claude | `file_operations`, `planning` | `render_syntax_tree` |
| Translate | OpenAI, Cohere, DeepSeek | — | `load_translation_context`, `save_translation_context`, `add_vocabulary_entry`, `clear_vocabulary` |
| Video Describer | OpenAI, Gemini, Grok | `video_analysis`, `planning` | — |
| Video Generator | Gemini, Grok | `planning` | `generate_video_with_veo` (Gemini), `monadic_load_state`, `generate_video_with_grok_imagine` (Grok) |
| Voice Chat | OpenAI, Claude, Gemini, Grok, Mistral, Cohere, DeepSeek, Ollama | — | — |
| Voice Interpreter | OpenAI, Cohere | — | `load_context`, `save_translation`, `set_target_language` |
| Web Insight | OpenAI, Claude, Gemini, Grok | `web_automation`, `planning` | — |
| Wikipedia | OpenAI | `web_search_tools` (conditional) | `search_wikipedia` |

App tool methods live in `apps/<app>/<app>_tools.rb` (or the app's `.rb` file); the DSL includes `<Base>Tools` and each imported group's module in the generated class.

## Regenerating the App Table

The table is derived from the MDSL files: `provider`, `display_name`, `import_shared_tools` (with `visibility`) and `define_tool` of each file, merged per app directory.
