# Tool Loop Prevention Testing

This document explains the testing strategies implemented to prevent infinite tool call loops in apps with `initiate_from_assistant: true`.

## The Problem

Apps with `initiate_from_assistant: true` can enter infinite tool call loops when:

1. The system prompt has aggressive mandatory tool usage language ("MUST", "MANDATORY", "CRITICAL ERROR")
2. The model follows instructions literally and calls tools repeatedly
3. Results in "Maximum function call depth exceeded" error

### Example of Problematic Pattern

```ruby
# BAD: This causes infinite loops
system_prompt <<~TEXT
  ## CRITICAL: MANDATORY TOOL USAGE

  **YOU MUST USE THE PROVIDED TOOLS. THIS IS NOT OPTIONAL.**

  Before ANY response, you MUST call tools in this order:
  1. **FIRST**: Call `load_research_progress`
  2. **ALWAYS**: Call `save_research_progress` with your response

  **FAILURE TO CALL THESE TOOLS IS A CRITICAL ERROR.**
TEXT
```

### Example of Safe Pattern

```ruby
# GOOD: This prevents loops
system_prompt <<~TEXT
  ## Initial Greeting (Important)
  When starting a new session with no prior user messages, simply greet the user
  and briefly explain your capabilities. Do NOT call any tools for the initial greeting.

  ## Research Progress Tracking (Recommended)

  You have tools to track your research progress. Use them when appropriate:
  - `load_research_progress`: Check existing research state
  - `save_research_progress`: Save your response with research findings

  ## Tool Usage (Important)
  - Call tools with purpose - avoid repeated calls with same parameters
  - **After calling `save_research_progress`, your turn is COMPLETE. Do NOT call any more tools.**
TEXT
```

## Testing Strategies

### 1. Static Analysis Test (`initiate_from_assistant_safety_spec.rb`)

**Location:** `spec/unit/apps/initiate_from_assistant_safety_spec.rb`

This test scans all MDSL files and checks:

- **Dangerous Patterns Detected:**
  - `MANDATORY.*TOOL`
  - `YOU MUST USE THE PROVIDED TOOLS`
  - `FAILURE TO CALL.*TOOLS.*IS.*CRITICAL`
  - `ABSOLUTE RULES.*ALWAYS call`
  - `Before ANY response.*you MUST call`
  - `NEVER skip tool calls`

- **Required Safeguards:**
  - Initial greeting exception (e.g., "Do NOT call tools for initial greeting")
  - Stop condition after save (e.g., "After calling save_*, your turn is COMPLETE")
  - Recommended language instead of mandatory (e.g., "when appropriate")

**Run:**
```bash
bundle exec rspec spec/unit/apps/initiate_from_assistant_safety_spec.rb
```

### 2. ResponseEvaluator Enhancements

**Location:** `spec/support/response_evaluator.rb`

Added patterns and checks:

- **TOOL_LOOP_ERROR_PATTERNS:** Detects error messages like "Maximum function call depth exceeded"
- **SAFE_INITIAL_TOOLS:** Tools acceptable in initial messages (load_* etc.)
- **RISKY_INITIAL_TOOLS:** Tools that should NOT be called in initial messages (save_*, add_*, update_*)

For initial messages (`is_initial_message: true`), the evaluator now:
1. Fails if response contains tool loop error text
2. Fails if risky tools are called
3. Fails if too many non-safe tools are called

### 3. Initial Message Matrix Test Improvements

**Location:** `spec/integration/provider_matrix/all_providers_all_apps_spec.rb`

The Initial Message Matrix test now:

1. **Checks for tool loop error patterns** in response text
2. **Validates tool calls** - fails if risky tools (save_*, update_*, add_*) are called
3. **Treats timeout as potential loop** - instead of skipping, now fails with diagnostic message
4. **Detects loop indicators in exceptions** - catches "Maximum function call depth" errors

## Tool Classification

### Safe Tools (OK in initial messages)
- `load_research_progress`
- `load_learning_progress`
- `load_novel_context`
- `load_context`
- `list_titles`
- `list_help_sections`
- `check_environment`

### Risky Tools (NOT OK in initial messages)
- `save_research_progress`
- `save_learning_progress`
- `save_novel_context`
- `save_response`
- `save_context`
- `add_finding`
- `add_research_topics`
- `add_sources`
- `update_progress`

## Fixing Apps with Issues

When the tests detect issues, fix the app by:

1. **Add Initial Greeting Exception:**
   ```
   ## Initial Greeting (Important)
   When starting a new session with no prior user messages, simply greet the user.
   Do NOT call any tools for the initial greeting - just respond with text.
   ```

2. **Change Mandatory to Recommended:**
   - Replace "MUST" with "should" or "can"
   - Replace "MANDATORY" with "Recommended"
   - Replace "CRITICAL ERROR" with descriptive guidance

3. **Add Clear Stop Condition:**
   ```
   **After calling `save_*`, your turn is COMPLETE. Do NOT call any more tools.**
   ```

4. **Consider reasoning_effort Setting:**
   - For OpenAI models, `reasoning_effort "none"` may reduce aggressive tool usage
   - Some features (like native web search) require `reasoning_effort "low"` or higher

## Running All Related Tests

```bash
# Static analysis
bundle exec rspec spec/unit/apps/initiate_from_assistant_safety_spec.rb

# Initial message matrix (requires API keys)
PROVIDERS=openai,anthropic,gemini RUN_API=true bundle exec rspec \
  spec/integration/provider_matrix/all_providers_all_apps_spec.rb \
  --tag initial_message

# With debug output
DEBUG=true PROVIDERS=openai RUN_API=true bundle exec rspec \
  spec/integration/provider_matrix/all_providers_all_apps_spec.rb
```

## Related Documentation

- [Testing Guide](testing_guide.md) - General testing approach
- [Model Spec Vocabulary](model_spec_vocabulary.md) - Model capability definitions
