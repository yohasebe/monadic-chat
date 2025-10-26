# System Prompt Injection Architecture

## Overview

Monadic Chat uses a unified prompt injection system (`SystemPromptInjector`) to dynamically augment AI prompts based on runtime conditions. This system replaced distributed injection logic that was previously scattered across 9 vendor helper files and websocket.rb.

## Architecture

### Core Module

**Location**: `docker/services/ruby/lib/monadic/utils/system_prompt_injector.rb`

The `SystemPromptInjector` module provides:
- Rule-based injection system with priority ordering
- Separate contexts for system messages and user messages
- Graceful error handling
- Consistent separator management

### Two Injection Contexts

1. **System Context** (`:system`)
   - Applied once at conversation start
   - Modifies the initial system message
   - Currently has 5 active rules

2. **User Context** (`:user`)
   - Applied to each user input
   - Appends instructions to user messages
   - Currently has 1 active rule

## Current Injection Rules

### System Context Rules (Priority Order)

| Priority | Rule Name | Condition | Purpose |
|----------|-----------|-----------|---------|
| 100 | `language_preference` | User sets language (not "auto") | Enforce response language |
| 80 | `websearch` | Websearch enabled + non-reasoning model | Add web search instructions |
| 60 | `stt_diarization_warning` | STT model contains "diarize" | Warn about speaker label interpretation |
| 50 | `mathjax` | MathJax enabled | Add LaTeX/MathJax formatting instructions |
| 40 | `system_prompt_suffix` | Suffix provided in options | Append custom system prompt suffix |

### User Context Rules (Priority Order)

| Priority | Rule Name | Condition | Purpose |
|----------|-----------|-----------|---------|
| 10 | `prompt_suffix` | Suffix provided in settings | Append instructions to each user input |

## Rule Structure

Each injection rule is a hash with four components:

```ruby
{
  name: :rule_name,           # Symbol identifier
  priority: 100,              # Higher = earlier in output
  condition: ->(session, options) {
    # Lambda that returns true/false
    # Has access to session and options
  },
  generator: ->(session, options) {
    # Lambda that returns the text to inject
    # Only called if condition is true
  }
}
```

## Adding a New Injection Rule

### Step 1: Define the Prompt Content

Add constants for your prompt content at the top of `system_prompt_injector.rb`:

```ruby
# Use <<~'PROMPT' (single quotes) if content contains backslashes
MY_FEATURE_PROMPT = <<~'PROMPT'.strip
  Your prompt content here.
  Use single quotes to preserve backslashes literally.
PROMPT
```

### Step 2: Add the Rule

Add your rule to the appropriate array:

```ruby
# For system context
SYSTEM_INJECTION_RULES = [
  # ... existing rules ...
  {
    name: :my_feature,
    priority: 45,  # Choose based on desired order
    condition: ->(session, _options) {
      # Check session parameters or runtime settings
      session[:parameters]&.[]("my_feature") == true
    },
    generator: ->(_session, _options) {
      MY_FEATURE_PROMPT
    }
  }
].freeze

# For user context
USER_INJECTION_RULES = [
  # ... existing rules ...
  {
    name: :my_user_feature,
    priority: 15,
    condition: ->(_session, options) {
      !options[:my_setting].to_s.empty?
    },
    generator: ->(_session, options) {
      options[:my_setting].to_s.strip
    }
  }
].freeze
```

### Step 3: Update Vendor Helper Calls

The unified system is already integrated into all 9 vendor helpers. No changes needed unless you're adding new options to pass through.

If you need to pass new options:

```ruby
augmented_prompt = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: initial_prompt,
  session: session,
  options: {
    websearch_enabled: websearch_enabled,
    # Add your new option here
    my_setting: obj["my_setting"]
  }
)
```

### Step 4: Add Tests

Add test cases to `docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`:

```ruby
context 'with my feature enabled' do
  it 'includes my feature prompt' do
    session = {
      parameters: { "my_feature" => true }
    }
    options = {}

    result = described_class.build_injections(session: session, options: options)

    expect(result.length).to eq(1)
    expect(result[0][:name]).to eq(:my_feature)
    expect(result[0][:content]).to include('expected content')
  end

  it 'excludes my feature when disabled' do
    session = {
      parameters: { "my_feature" => false }
    }
    options = {}

    result = described_class.build_injections(session: session, options: options)

    expect(result).to be_empty
  end
end
```

### Step 5: Update Priority Order Test

Update the "with multiple conditions met" test to include your new rule:

```ruby
expect(result.length).to eq(6)  # Increment count
# Add expectation for your rule in priority order
expect(result[3][:name]).to eq(:my_feature)  # Adjust index based on priority
```

## Usage Examples

### Basic System Prompt Augmentation

```ruby
augmented = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: "You are a helpful assistant.",
  session: session,
  options: {
    websearch_enabled: true,
    websearch_prompt: "Search the web when needed.",
    system_prompt_suffix: "Always be concise."
  }
)
```

### User Message Augmentation

```ruby
augmented = Monadic::Utils::SystemPromptInjector.augment_user_message(
  base_message: "What is the weather?",
  session: session,
  options: {
    prompt_suffix: "Respond in one sentence."
  }
)
```

### Manual Injection Building

```ruby
injections = Monadic::Utils::SystemPromptInjector.build_injections(
  session: session,
  options: options,
  context: :system
)

# Returns array of hashes: [{ name: :rule_name, content: "text" }, ...]
```

## Implementation Details

### Priority Ordering

Rules are executed in descending priority order (100 → 10). This ensures:
- Language settings applied first (most fundamental)
- Feature-specific prompts in the middle
- User customizations last (most specific)

### Error Handling

The system includes graceful error handling:
- If a condition evaluation fails, the rule is skipped
- If a generator fails, the rule is skipped
- Errors are logged when `EXTRA_LOGGING=true`
- Empty content is automatically filtered out

### Separator Management

Default separators:
- System context: `"\n\n---\n\n"` (clearly demarcated sections)
- User context: `"\n\n"` (simple paragraph break)

Custom separators can be specified:

```ruby
augmented = SystemPromptInjector.augment(
  base_prompt: prompt,
  session: session,
  options: options,
  separator: "\n\n"  # Custom separator
)
```

### String Escaping in Constants

**Important**: When defining prompt constants that contain backslashes (e.g., LaTeX/MathJax), use single-quoted heredocs:

```ruby
# WRONG - Backslashes will be interpreted
MY_LATEX_PROMPT = <<~PROMPT
  Use \frac{a}{b} for fractions.
PROMPT
# Result: "Use rac{a}{b}" (backslash consumed!)

# CORRECT - Backslashes preserved literally
MY_LATEX_PROMPT = <<~'PROMPT'
  Use \frac{a}{b} for fractions.
PROMPT
# Result: "Use \frac{a}{b}" (backslash preserved!)
```

## Migration History

### Before: Distributed Implementation

Prior to 2025-01, prompt injection logic was scattered across:
- 9 vendor helper files (`*_helper.rb`): ~200 lines of duplicated code
- `websocket.rb`: Additional injections for MathJax (~45 lines)

Problems:
- New features required changes to 9 separate files
- Inconsistent implementation across vendors
- Different separators and injection points
- Difficult to maintain and test

### After: Unified System

Current implementation (2025-01):
- Single source of truth in `system_prompt_injector.rb`
- Automatic availability to all 9 vendors
- Consistent behavior and testing
- New features require ~10 lines of code (1 rule definition)

### Migration Process

All 9 vendor helpers were refactored:
1. OpenAI Helper
2. Claude Helper
3. Gemini Helper
4. Mistral Helper
5. DeepSeek Helper
6. Cohere Helper
7. Grok Helper
8. Perplexity Helper
9. Ollama Helper

Each now uses:
```ruby
require_relative "../../utils/system_prompt_injector"

# System message augmentation
augmented_prompt = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: initial_prompt,
  session: session,
  options: options
)

# User message augmentation
augmented_text = Monadic::Utils::SystemPromptInjector.augment_user_message(
  base_message: user_input,
  session: session,
  options: { prompt_suffix: prompt_suffix }
)
```

## Special Cases

### MathJax Injection

MathJax requires different escaping for different modes:
- **Regular mode**: Single backslash (`\frac`)
- **Monadic/Jupyter mode**: Double backslash (`\\frac`) for JSON serialization

The MathJax rule handles this automatically:

```ruby
{
  name: :mathjax,
  priority: 50,
  condition: ->(session, _options) {
    session[:parameters]&.[]("mathjax") == true
  },
  generator: ->(session, _options) {
    parts = [MATHJAX_BASE_PROMPT]

    monadic_mode = session[:parameters]&.[]("monadic") == true
    jupyter_mode = session[:parameters]&.[]("jupyter") == true

    if monadic_mode || jupyter_mode
      parts << MATHJAX_MONADIC_PROMPT  # Double-escaped
    else
      parts << MATHJAX_REGULAR_PROMPT  # Single-escaped
    end

    parts.join("\n\n")
  }
}
```

### STT Diarization Warning

When using diarization-enabled STT models (e.g., `gpt-4o-transcribe-diarize`), the AI might mistakenly adopt the role of one of the labeled speakers (A:, B:, C:). The diarization warning injection prevents this:

```ruby
{
  name: :stt_diarization_warning,
  priority: 60,
  condition: ->(session, _options) {
    stt_model = session[:parameters]&.[]("stt_model")
    stt_model && stt_model.to_s.include?("diarize")
  },
  generator: ->(_session, _options) {
    DIARIZATION_STT_PROMPT  # Warns AI not to adopt speaker roles
  }
}
```

## Testing

### Test Coverage

The system has comprehensive test coverage in `docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`:

- **Unit tests**: Each rule tested individually
- **Integration tests**: Multiple rules combined
- **Priority tests**: Correct ordering verified
- **Error handling tests**: Graceful degradation
- **Edge cases**: Empty strings, nil values, etc.

Current test count: 26 examples, 0 failures

### Running Tests

```bash
# Run all SystemPromptInjector tests (from docker/services/ruby directory)
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb

# Run with full descriptions
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb -fd

# Run specific context
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb -e "with MathJax enabled"
```

## Best Practices

1. **Priority Assignment**
   - Use intervals of 10-20 to allow future insertions
   - Language settings: 100
   - Feature toggles: 40-80
   - User customizations: 10-30

2. **Condition Checks**
   - Always use safe navigation (`&.[]`)
   - Check for nil and empty strings
   - Return boolean explicitly

3. **Generator Functions**
   - Strip whitespace with `.strip`
   - Handle nil values gracefully
   - Use constants for static content

4. **Testing**
   - Test both enabled and disabled states
   - Test with multiple conditions
   - Test error cases (nil session, missing keys)

5. **Documentation**
   - Add inline comments for complex logic
   - Update this document when adding rules
   - Document any special escaping needs

## Related Files

- **Implementation**: `docker/services/ruby/lib/monadic/utils/system_prompt_injector.rb`
- **Tests**: `docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`
- **Vendor Helpers**: `docker/services/ruby/lib/monadic/adapters/vendors/*_helper.rb`
- **Language Config**: `docker/services/ruby/lib/monadic/utils/language_config.rb`
