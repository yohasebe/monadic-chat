# Jupyter Notebook Architecture Documentation

## Overview

This document describes the architecture and implementation patterns for Jupyter Notebook integration across different AI providers in Monadic Chat.

## Session Context

All Jupyter Notebook apps (OpenAI, Claude, Gemini, xAI Grok) run with `monadic true`. The Jupyter tools save the notebook context, and the model reads it with `monadic_load_state`:

```ruby
monadic_load_state(app: "JupyterNotebook...", key: "context")
# Returns: {jupyter_running: true, notebook_created: true, notebook_filename: "example.ipynb", link: "..."}
```

## Provider-Specific Implementations

| Provider | File | Notes |
|---|---|---|
| OpenAI | `jupyter_notebook_openai.mdsl` | — |
| Claude | `jupyter_notebook_claude.mdsl` | — |
| Gemini | `jupyter_notebook_gemini.mdsl` | Uses `create_and_populate_jupyter_notebook` for creation plus cells; tool results are cleared at the start of each user turn; early termination check for cell operations |
| xAI Grok | `jupyter_notebook_grok.mdsl` | Uses `create_and_populate_jupyter_notebook`; function returns are cleared at the start of each user turn |

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

#### Automatic Error Verification

`add_jupyter_cells` verifies the execution itself. When `add_jupyter_cells(run: true)` is called:
1. **Automatic verification**: Tool internally calls `get_jupyter_cells_with_results` after execution
2. **Error detection**: Checks all cells for `has_error: true`
3. **Formatted response**:
   - Success: `✓ All N cells executed successfully without errors.`
   - Errors: `⚠️  ERRORS DETECTED IN NOTEBOOK:` with cell index, error type, message
   - Unexpected verification output: `⚠️  Could not verify cell execution: …`
4. The error information is part of the tool response

**Implementation**: `add_jupyter_cells` in `lib/monadic/adapters/jupyter_helper.rb`

#### Error Fixing Workflow

The system prompts allow at most 2 retry attempts:
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
