# Tool Analysis: Complete Index

## Overview

This directory contains a comprehensive analysis of all tool definitions in Monadic Chat MDSL files, identifying opportunities for creating new shared tool groups.

**Analysis Date**: 2025-10-29
**Total Tools Found**: 66
**Ungrouped Tools Identified**: 51
**Grouping Opportunities**: 12+

## Files in This Analysis

### 1. TOOL_QUICK_REFERENCE.txt (START HERE)
- Quick overview of findings
- Top 3 grouping opportunities
- Complete categorized tool lists
- Implementation priorities
- **Best for**: Quick lookup and executive briefing

### 2. TOOL_ANALYSIS_REPORT.md (COMPREHENSIVE)
- Complete detailed analysis (21 KB)
- All 12+ tool groups explained
- Parameter patterns for each tool
- Implementation recommendations
- 66-tool inventory table
- Single-app tools (not grouping candidates)
- **Best for**: Implementation planning and detailed reference

### 3. TOOL_GROUPING_SUMMARY.txt (STRATEGIC)
- Executive summary (8.6 KB)
- Phase-based implementation roadmap
- Key observations and patterns
- Emerging patterns (vector DB, agent delegation)
- Future-proof extensibility notes
- **Best for**: Strategic planning and architecture decisions

## Quick Facts

| Metric | Value |
|--------|-------|
| Total unique tools | 66 |
| Already grouped (5 groups) | 15 |
| Ready for new groups | 51 |
| Highest frequency tool | second_opinion_agent (9 uses) |
| Largest group | jupyter_operations (19 tools) |
| Most critical group | jupyter_operations (eliminates 76 lines duplication) |

## Top 3 Grouping Opportunities

### 🔴 #1: JUPYTER OPERATIONS (19 tools, 4 app families)
**Status**: CRITICAL - Ready to implement immediately
- Used in: jupyter_notebook (openai, grok, claude, gemini)
- Example tools: run_jupyter, add_jupyter_cells, update_jupyter_cell
- Consolidation opportunity: ~76 lines of MDSL duplication
- Consistency: 100% shareable across providers

### 🟡 #2: WEB EXPLORATION (4 tools, 4 app families)
**Status**: HIGH PRIORITY - Ready to implement
- Used in: visual_web_explorer (claude, openai, gemini, grok)
- Tools: capture_viewport_screenshots, capture_webpage_text, get_viewport_presets, list_captured_screenshots
- Consolidation opportunity: ~16 lines of duplication
- Consistency: Unified Selenium backend

### 🟡 #3: IMAGE GENERATION (3 tools, 3 app families)
**Status**: HIGH PRIORITY - Ready to implement
- Used in: image_generator (openai, gemini, grok)
- Tools: generate_image_with_openai, generate_image_with_gemini, generate_image_with_grok
- Consolidation opportunity: ~12 lines of duplication
- Consistency: Consistent multi-provider interface

## Complete Tool Groups

### Priority 1: High Impact (3 groups)
1. **jupyter_operations** - 19 tools across 4 app families
2. **web_exploration** - 4 tools across 4 app families
3. **image_generation** - 3 tools across 3 app families

### Priority 2: Medium Impact (4 groups)
4. **agent_delegation** - gpt5_codex_agent, grok_code_agent (6+ app families)
5. **web_search_tools** - tavily_search, tavily_fetch, websearch_agent (3+ apps)
6. **video_generation** - generate_video_with_sora, generate_video_with_veo (1-2 apps, extensible)
7. **auto_forge** - 5 app generation tools (auto_forge app family)

### Priority 3: Lower Impact but Valuable (5+ groups)
8. **diagram_generation/mermaid_tools** - 4+ diagram tools
9. **pdf_navigation** - 4 PDF search tools
10. **documentation_search** - 4 help/docs tools
11. **content_analysis** - analyze_image, analyze_audio, analyze_video
12. **text_to_speech** - text_to_speech, list_providers_and_voices

## Single-App Tools (Not Candidates for Grouping)
- second_opinion_agent (9 uses, but second_opinion app only)
- request_tool (research_assistant specific)
- search_wikipedia (wikipedia app specific)
- Music theory tools: validate_chord_progression, validate_abc_syntax, analyze_abc_error (chord_accompanist)
- count_num_of_words, count_num_of_chars (novel_writer)

## Implementation Recommendations

### Phase 1: Immediate (Quick Win)
Create 3 high-impact groups:
1. jupyter_operations
2. web_exploration
3. image_generation

**Expected ROI**: ~104 lines of MDSL duplication eliminated, consistent experience across 11 app family combinations

### Phase 2: Short-term (Medium Effort)
Create 4 medium-impact groups:
4. agent_delegation
5. video_generation
6. web_search_tools
7. auto_forge standardization

**Expected ROI**: Code delegation unification, media generation framework

### Phase 3: Long-term (Nice-to-have)
Create 5+ lower-impact but valuable groups:
- diagram_generation
- pdf_navigation
- documentation_search
- content_analysis
- text_to_speech

**Expected ROI**: Enable new apps to leverage existing capabilities

## Key Observations

1. **Jupyter tools are the most critical** - 19 tools duplicated across 4 provider variants
2. **Web exploration is fully shareable** - Unified Selenium backend, no provider differences
3. **Vector database pattern emerging** - pdf_navigator and monadic_help both use PGVector
4. **Agent delegation can be unified** - Both gpt5_codex_agent and grok_code_agent follow same pattern
5. **Media generation convergence** - image_generation + video_generation could unify as media_generation

## Parameter Patterns by Category

### Jupyter Operations
- filename, cells, index, content, cell_type, command, run, escaped

### Web Exploration
- url, viewport_width, viewport_height, overlap, preset

### Image Generation
- prompt, size, style, quality, n, edit_instructions

### Video Generation
- prompt, duration, resolution, aspect_ratio, model, quality

### Web Search
- query, url, max_results, include_images

### PDF/Document Search
- query, doc_id, snippet_id, limit, similarity_threshold

## How to Use This Analysis

### For Quick Overview
→ Start with TOOL_QUICK_REFERENCE.txt

### For Implementation Planning
→ Read TOOL_GROUPING_SUMMARY.txt for roadmap, then TOOL_ANALYSIS_REPORT.md for details

### For Detailed Reference
→ Use TOOL_ANALYSIS_REPORT.md for complete tool inventory and parameter patterns

### For Architectural Decisions
→ Review key observations and emerging patterns in TOOL_GROUPING_SUMMARY.txt

## File Locations

All analysis files are located in the repository root:
- `/Users/yohasebe/code/monadic-chat/TOOL_QUICK_REFERENCE.txt`
- `/Users/yohasebe/code/monadic-chat/TOOL_ANALYSIS_REPORT.md`
- `/Users/yohasebe/code/monadic-chat/TOOL_GROUPING_SUMMARY.txt`
- `/Users/yohasebe/code/monadic-chat/TOOL_ANALYSIS_INDEX.md` (this file)

## Search Coverage

This analysis examined:
- All MDSL files in `/docker/services/ruby/apps/`
- 66 unique `define_tool` declarations
- 20+ app families
- 4+ provider variants per app
- Parameter patterns and consistency

## Related Documentation

For implementation:
- See `CLAUDE.md` for development guidelines
- See `docs_dev/` for architecture documentation
- See existing shared tool group implementations for reference
