# Jupyter Notebook Architecture Documentation

## Overview

This document describes the architecture and implementation patterns for Jupyter Notebook integration across different AI providers in Monadic Chat.

## Key Architectural Decision: Monadic vs Non-Monadic Mode

### The Challenge

Different AI providers have different approaches to maintaining conversation context:
- **Monadic Mode**: Structured JSON responses that naturally preserve state
- **Non-Monadic Mode**: Natural language responses that don't inherently maintain context

### Provider Configurations

| Provider | Monadic Mode | Reason |
|----------|--------------|--------|
| OpenAI | `true` | Supports both JSON structure and tool execution |
| Claude | `true` | Uses Session State for notebook context tracking |
| Gemini | `true` | Uses Session State for notebook context tracking |
| xAI Grok | `true` | Uses Session State for notebook context tracking |

> **Note (Updated 2025-12-31)**: All providers now use `monadic true` for consistent session state management via `monadic_load_state` tool.

## Session Context Management

### Current Implementation (Updated 2025-12-31)

All providers now use `monadic true` with the `monadic_load_state` tool for automatic session state management.

The notebook context is automatically saved by Jupyter tools and can be retrieved using:
```ruby
monadic_load_state(app: "JupyterNotebook...", key: "context")
# Returns: {jupyter_running: true, notebook_created: true, notebook_filename: "example.ipynb", link: "..."}
```

### Historical Context (2025-08-28)

Previously, non-monadic providers experienced issues where:
1. User creates a notebook (e.g., `math_notebook_20250828_123456`)
2. User asks to add cells to the notebook
3. AI creates a NEW notebook instead of adding to the existing one
4. Root cause: Missing session context tracking

This was resolved by converting all providers to use `monadic true` with shared `monadic_load_state` tool.

## Provider-Specific Implementations

### OpenAI
- **File**: `jupyter_notebook_openai.mdsl`
- **Monadic**: `true`
- **Context Tracking**: Automatic via JSON structure
- **Special Handling**: None required

### Claude
- **File**: `jupyter_notebook_claude.mdsl`
- **Monadic**: `true`
- **Context Tracking**: Automatic via `monadic_load_state` tool
- **Special Handling**: Batch processing to reduce API calls

### Gemini
- **File**: `jupyter_notebook_gemini.mdsl`
- **Monadic**: `true`
- **Context Tracking**: Automatic via `monadic_load_state` tool
- **Special Handling**:
  - Tool results cleared at user turn start (robustness)
  - Early termination check for Jupyter cell operations

### xAI Grok
- **File**: `jupyter_notebook_grok.mdsl`
- **Monadic**: `true`
- **Context Tracking**: Automatic via `monadic_load_state` tool
- **Special Handling**:
  - Uses `create_and_populate_jupyter_notebook` for combined creation + cells
  - Function returns cleared at user turn start (robustness)

## Common Patterns

### Filename Handling

All providers must handle timestamped filenames correctly:
```
create_jupyter_notebook("math_notebook")
→ Returns: "math_notebook_20250828_123456.ipynb"
→ Must use: "math_notebook_20250828_123456" for subsequent operations
```

### Cell Structure

Standard cell format across all providers:
```json
{
  "cell_type": "code" | "markdown",
  "source": "code or markdown content"
}
```

### Error Handling

#### Automatic Error Verification (Implemented 2025-10-21)

**Problem**: AI agents were not consistently checking for errors after adding cells, leading to silent failures where cells appeared to be added successfully but actually contained errors.

**Solution**: Built-in automatic verification in `add_jupyter_cells` tool.

When `add_jupyter_cells(run: true)` is called:
1. **Automatic verification**: Tool internally calls `get_jupyter_cells_with_results` after execution
2. **Error detection**: Checks all cells for `has_error: true`
3. **Formatted response**:
   - Success: `✓ All N cells executed successfully without errors.`
   - Errors: `⚠️  ERRORS DETECTED IN NOTEBOOK:` with cell index, error type, message
4. **AI awareness**: Error information is automatically included in tool response

**Benefits**:
- Eliminates reliance on AI remembering to verify
- Ensures errors are always detected and reported
- Clear, consistent error reporting format
- No need for manual `get_jupyter_cells_with_results` calls

**Implementation**: `lib/monadic/adapters/jupyter_helper.rb` lines 415-446

#### Error Fixing Workflow

Maximum 2 retry attempts to prevent infinite loops:
1. **Detection**: Tool automatically reports errors with cell index and error type
2. **Analysis**: AI reads error summary from tool response
3. **Full details** (if needed): Call `get_jupyter_cells_with_results` for complete traceback
4. **Fix**: Use `update_jupyter_cell(filename:, index:, content:)` to replace problematic cell
5. **Verification**: Re-run with `run_jupyter_cells` to confirm fix

## Testing Considerations

### Key Test Scenarios

1. **Initial Creation**: Can create notebook with cells
2. **Subsequent Addition**: Can add cells to existing notebook
3. **Context Preservation**: Remembers imports and variables
4. **Error Recovery**: Handles cell execution errors gracefully

### Provider-Specific Tests

**Matrix Test (All Providers):**
- `spec/integration/provider_matrix/all_providers_all_apps_spec.rb` - Smoke tests for all provider × app combinations

**Individual Tests:**
- `spec/integration/jupyter_notebook_gemini_spec.rb` - Gemini-specific tests
- `spec/e2e/jupyter_notebook_grok_spec.rb` - Grok-specific tests
- `spec/integration/jupyter_notebook_operations_spec.rb` - Shared operations tests
- `spec/unit/adapters/jupyter_helper_spec.rb` - Unit tests for jupyter_helper.rb

## Lessons Learned

1. **Unified Mode is Better**: Standardizing all providers to `monadic true` simplified context management
2. **Robustness Features Matter**: Tool result clearing at turn start and early termination checks prevent duplicate processing
3. **Shared Tools Work Well**: `jupyter_operations` shared tools provide consistent interface across providers
4. **Testing Critical**: Session context issues only appear in multi-turn conversations

## Recent Improvements (2025-12-31)

1. **Unified Monadic Mode**: All providers now use `monadic true`
2. **Robustness Features**: Added tool result clearing and early termination checks for Gemini and Grok
3. **Pattern Matching Fixes**: Fixed Grok's notebook link display issue
