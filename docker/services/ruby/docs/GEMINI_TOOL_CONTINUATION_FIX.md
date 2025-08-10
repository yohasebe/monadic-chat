# Gemini Tool Continuation Fix & Known Limitations

## Problem
The Gemini Jupyter Notebook app was experiencing an issue where it could not continue making function calls after processing tool results. The error logs showed:

```json
"tool_config": {
  "function_calling_config": {
    "mode": "NONE"
  }
}
```

This prevented Gemini from making subsequent function calls in multi-turn conversations, causing errors like:
- `exec: "node": executable file not found in $PATH: unknown`

## Root Cause
In `/lib/monadic/adapters/vendors/gemini_helper.rb`, when processing tool results (role == "tool"), the code was setting `function_calling_config.mode` to "NONE", which disabled further function calling.

## Solution
Modified the Gemini helper to:
1. Keep `function_calling_config.mode` as "ANY" when tools are available
2. Re-add the tools configuration after processing tool results
3. Only set mode to "NONE" when no tools are configured

### Code Changes
**File**: `/lib/monadic/adapters/vendors/gemini_helper.rb` (lines 654-692)

**Before**:
```ruby
if role == "tool"
  # ... process tool results ...
  body["tool_config"] = {
    "function_calling_config" => {
      "mode" => "NONE"  # This disabled further function calls
    }
  }
end
```

**After**:
```ruby
if role == "tool"
  # ... process tool results ...
  
  # Keep tools available for continued function calling
  if app_tools && !app_tools.empty?
    body["tool_config"] = {
      "function_calling_config" => {
        "mode" => "ANY"  # Keep function calling enabled
      }
    }
    # Re-add tools for continued function calling
    if app_tools.is_a?(Hash) && app_tools["function_declarations"]
      body["tools"] = [{"function_declarations" => app_tools["function_declarations"]}]
    elsif app_tools.is_a?(Array)
      body["tools"] = [{"function_declarations" => app_tools}]
    else
      body["tools"] = [app_tools]
    end
  else
    # Only set to NONE if no tools are configured
    body["tool_config"] = {
      "function_calling_config" => {
        "mode" => "NONE"
      }
    }
  end
end
```

## Impact
This fix enables:
1. **Continuous Function Calling**: Gemini can now make multiple function calls in a single conversation
2. **Better User Experience**: No more errors when executing sequences of operations
3. **Full Jupyter Notebook Support**: Users can create notebooks, add cells, and execute code in a natural flow

## Testing
Added integration tests to verify:
- Tools remain available after processing tool results
- Function calling continues to work in multi-turn conversations
- All 16 Jupyter Notebook Gemini tests pass

## Known Limitations and Important Discoveries

### Gemini 2.5 Models - Function Calling vs Structured Output Trade-off
**Discovery**: Gemini 2.5 models have a fundamental trade-off between function calling and structured JSON output. You cannot have both simultaneously.

#### For Function Calling
**Requirement**: Must use `reasoning_effort: minimal` in MDSL configuration
```ruby
llm do
  provider "gemini"
  model ["gemini-2.5-flash", "gemini-2.0-flash"]
  reasoning_effort "minimal"  # REQUIRED for function calls
end
```

**Without `reasoning_effort: minimal`**:
- Model generates pseudo-code instead of actual function calls
- Outputs `<execute_ipython>` tags rather than making API calls
- Function declarations are ignored

#### For Structured JSON Output (Monadic Mode)
**Requirement**: Must NOT include `reasoning_effort` parameter
```ruby
llm do
  provider "gemini"
  model ["gemini-2.5-flash", "gemini-2.0-flash"]
  # NO reasoning_effort parameter
end
```

**With `reasoning_effort` in monadic mode**:
- JSON gets wrapped in markdown code blocks (```json```)
- Breaks JSON parsing in the UI
- Context information becomes inaccessible

#### Solution Strategy by App Type

**Apps with Heavy Function Calling**:
- Jupyter Notebook: Use `reasoning_effort: minimal`
- Code Interpreter: Use `reasoning_effort: minimal`
- Research Assistant: Use `reasoning_effort: minimal`

**Apps with Structured JSON (Monadic Mode)**:
- Chat Plus: Remove `reasoning_effort` parameter
- Language Practice Plus: Remove `reasoning_effort` parameter
- Novel Writer: Remove `reasoning_effort` parameter

**Additional Requirements for Monadic Apps**:
Add explicit instructions in system prompt:
```
Requirements:
- The response MUST be valid JSON - no text before or after the JSON object
- DO NOT wrap the JSON in markdown code blocks (no ```json or ```)
- Start directly with { and end with }
```

### Tool Management Optimization
**Implementation**: Separate info-gathering tools from action tools to prevent exhausting tool call limits

**Info Tools** (no call limits):
- `get_jupyter_cells_with_results`
- `list_jupyter_notebooks`

**Action Tools** (limited to 5 calls):
- `create_jupyter_notebook`
- `run_jupyter`
- `add_jupyter_cells`
- Other modification operations

This separation allows unlimited read operations while preserving action tool quota for actual modifications.

### Migration to Gemini 2.5 Flash
**Recommendation**: Use `gemini-2.5-flash` as primary model with `gemini-2.0-flash` fallback
- Better cost/performance ratio than Pro models
- Faster response times
- Sufficient quality for most use cases

**Configuration**:
```ruby
model ["gemini-2.5-flash", "gemini-2.0-flash"]  # Array format for fallback
```

## Related Files
- `/apps/jupyter_notebook/jupyter_notebook_gemini.mdsl` - Gemini Jupyter Notebook app definition
- `/lib/monadic/dsl.rb` - DSL support for array-based tool definitions
- `/spec/integration/gemini_tool_continuation_integration_spec.rb` - Integration test for fix
- `/spec/integration/jupyter_notebook_gemini_spec.rb` - Main integration tests
- `/spec/e2e/jupyter_notebook_gemini_e2e_spec.rb` - End-to-end tests