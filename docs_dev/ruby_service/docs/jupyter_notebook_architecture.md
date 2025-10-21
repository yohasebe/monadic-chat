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
| Claude | `false` | Thinking blocks conflict with JSON structure |
| Gemini | `false` | Must choose between function calling OR structured output |
| xAI Grok | `false` | Cannot use monadic mode with tool execution |

## Session Context Management

### The Problem (Discovered 2025-08-28)

Non-monadic providers (Claude, Gemini, Grok) were experiencing issues where:
1. User creates a notebook (e.g., `math_notebook_20250828_123456`)
2. User asks to add cells to the notebook
3. AI creates a NEW notebook instead of adding to the existing one
4. Root cause: Missing session context tracking instructions

### The Solution

#### For Monadic Providers (OpenAI)

No special handling needed. The JSON structure automatically maintains:
```json
{
  "context": {
    "current_notebook": "math_notebook_20250828_123456",
    "imported_modules": ["numpy", "matplotlib"],
    "defined_functions": ["calculate_derivative", "plot_graph"]
  }
}
```

#### For Non-Monadic Providers (Claude, Gemini, Grok)

Must explicitly instruct in system prompt:

```markdown
## Session Context Tracking (CRITICAL)

Throughout the entire conversation session, you MUST:
1. **Remember the current notebook filename** you're working with (including timestamp)
2. **Track all variables, functions, and modules** used across cells
3. **Maintain awareness of notebook state** (what cells exist, what's been imported)
4. When user asks to add more cells, use the SAME notebook filename from earlier
5. Don't create new notebooks unless explicitly requested

Example conversation flow:
- User: "Create a math notebook" → You create "math_notebook_20250828_123456"
- User: "Add a function to calculate derivatives" → Use add_jupyter_cells with "math_notebook_20250828_123456"
- User: "Now add integration functions" → Still use "math_notebook_20250828_123456"
```

## Provider-Specific Implementations

### OpenAI
- **File**: `jupyter_notebook_openai.mdsl`
- **Monadic**: `true`
- **Context Tracking**: Automatic via JSON structure
- **Special Handling**: None required

### Claude
- **File**: `jupyter_notebook_claude.mdsl`
- **Monadic**: `false`
- **Context Tracking**: Explicit instruction: "Track variables, functions, and modules used across the session"
- **Special Handling**: Batch processing to reduce API calls

### Gemini
- **File**: `jupyter_notebook_gemini.mdsl`
- **Monadic**: `false`
- **Context Tracking**: Added explicit instructions (2025-08-28)
- **Special Handling**: 
  - Combined function `create_and_populate_jupyter_notebook` for initial creation
  - Cannot make multiple sequential function calls in one turn

### xAI Grok
- **File**: `jupyter_notebook_grok.mdsl`
- **Monadic**: `false`
- **Context Tracking**: Added explicit instructions (2025-08-28)
- **Special Handling**: Status block required at end of each response

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

**Implementation**: `lib/monadic/adapters/jupyter_helper.rb` lines 421-446

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

- `spec/integration/jupyter_notebook_openai_spec.rb`
- `spec/integration/jupyter_notebook_claude_spec.rb`
- `spec/integration/jupyter_notebook_gemini_spec.rb`
- `spec/integration/jupyter_notebook_grok_spec.rb`

## Lessons Learned

1. **Explicit is Better**: Non-monadic providers need explicit context tracking instructions
2. **Provider Limitations**: Some providers (Gemini) cannot chain multiple tool calls
3. **Workarounds**: Combined functions can overcome sequential call limitations
4. **Testing Critical**: Session context issues only appear in multi-turn conversations

## Future Improvements

1. **Unified Context Manager**: Create a shared context management system for non-monadic providers
2. **Automatic Fallback**: Detect when context is lost and recover automatically
3. **Session Persistence**: Save notebook context between sessions
4. **Provider Abstraction**: Hide provider-specific quirks behind a common interface