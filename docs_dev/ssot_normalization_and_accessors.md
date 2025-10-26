**SSOT Normalization and Accessors (Internal)**

This document describes the server-side normalization layer and canonical accessors for model capabilities. It helps Monadic Chat contributors maintain a single vocabulary across providers while staying backward compatible.

**Goals**
- Centralize capability semantics in `model_spec.js` (SSOT).
- Avoid hardcoded model lists/regex in helpers; prefer spec flags.
- Provide a normalization pass to map provider-specific aliases to canonical names.
- Offer stable accessors with conservative defaults.

**Normalization (ModelSpec.normalize_spec)**
- Runs after base spec load and user overrides merge.
- Converts aliases into canonical properties without removing originals:
  - `reasoning_model` → `is_reasoning_model`
  - `websearch_capability` / `websearch` → `supports_web_search`
  - `is_slow_model` → `latency_tier: "slow"`
  - `responses_api: true` → `api_type: "responses"`
- Does NOT auto-populate `supports_pdf_upload` (explicit per model to avoid behavior changes).

**Canonical Accessors**
- Prefer these over raw `get_model_property` calls:
  - `tool_capability?(model)`: Non‑false → true
  - `supports_streaming?(model)`: nil→true, else boolean
  - `vision_capability?(model)`: nil→true, else boolean
  - `supports_pdf?(model)`: boolean
  - `supports_pdf_upload?(model)`: boolean
  - `supports_web_search?(model)`: boolean
  - `responses_api?(model)`: boolean

**Helper Guidelines**
- Streaming: Gate by `supports_streaming?`; default to true for undefined.
- Tools: Gate by `tool_capability?`; drop `tools/tool_choice` for false.
- Vision/PDF: Validate before assembling content parts. For URL‑only PDFs, return a clear error (or instruct the user) instead of attaching base64.
- Reasoning: Use `is_reasoning_model`/`reasoning_effort` where applicable; avoid string matching on model names.
- Web search: Use `supports_web_search?` (and provider’s native config) instead of hardcoded lists.
- Audit: When `EXTRA_LOGGING` is enabled, log a single‑line capability summary including the source (spec/fallback/legacy).

**UI Guidance (Cross‑team)**
- The file–attach button is controlled by app features + `vision_capability`.
- Show “Image/PDF” only if `supports_pdf_upload: true`; otherwise show “Image”.
- Keep URL‑only PDF models (`supports_pdf: true`, `supports_pdf_upload: false`) consistent: do not allow `.pdf` in the file input.

**Migration Plan**
- New helpers should use accessors from day one.
- Existing helpers can migrate incrementally:
  1) Replace hardcoded lists with accessors
  2) Add capability audit lines
  3) Remove dead/legacy code paths after stabilization

**Testing**
- Add unit tests for:
  - Normalization mapping (aliases → canonical)
  - Accessor defaults (nil → expected default)
  - URL‑only PDFs (Perplexity) vs file uploads (Claude/Gemini/OpenAI) behaviors
- In system tests, validate button labels/accept attributes reflect SSOT flags.

---

## Multi-Provider SSOT Strategy

### Architectural Vision

**Goals**:
1. **Centralize all capability definitions in `model_spec.js`**: Single source of truth for all model capabilities across all providers
2. **Eliminate provider-specific hardcoded logic**: Move model name pattern matching and capability checks from helpers to SSOT
3. **Enable consistent cross-provider behavior**: Same capability means same behavior regardless of provider

### Common Implementation Pattern

All provider helpers should follow this structure:

```ruby
# ❌ Bad: Hardcoded capability checks
class ProviderHelper
  def supports_thinking?(model)
    model.include?('sonnet-4.5') || model.include?('opus-4')  # Hardcoded
  end

  def context_window(model)
    case model
    when /opus-4/
      200_000
    when /sonnet-4.5/
      200_000
    else
      100_000
    end
  end
end

# ✅ Good: SSOT-based implementation
class ProviderHelper
  def supports_thinking?(model)
    ModelSpec.supports_extended_thinking?(model, provider_name)  # Uses SSOT
  end

  def context_window(model)
    ModelSpec.context_window(model, provider_name)  # Uses SSOT
  end
end
```

### Provider Migration Roadmap

Each provider helper follows the same migration pattern:

**Phase 1: Inventory**
1. Identify all hardcoded capability checks
2. Map to canonical `model_spec.js` vocabulary
3. Document rationale for each hardcoded pattern

**Phase 2: Add SSOT Definitions**
1. Add capability definitions to `model_spec.js` for all models
2. Verify completeness and accuracy
3. Add unit tests for SSOT accessors

**Phase 3: Migrate Helper Code**
1. Replace hardcoded checks with SSOT accessors
2. Add logging for capability audit (when `EXTRA_LOGGING=true`)
3. Test against real provider APIs

**Phase 4: Remove Legacy Code**
1. Delete hardcoded capability logic
2. Remove obsolete helper methods
3. Update documentation

### Risk Mitigation Strategies

**1. Phased Rollout**
- Migrate one provider at a time
- Complete testing before moving to next provider
- Monitor production behavior after each migration

**2. Backward Compatibility**
- Accessors provide conservative defaults when spec undefined
- Fallback to hardcoded logic if SSOT lookup fails
- Log warnings when using fallback values

**3. Comprehensive Testing**
- Unit tests for each accessor with various inputs
- Integration tests with real provider APIs
- Regression tests for critical workflows

**4. Audit Logging**
- Enable `EXTRA_LOGGING=true` to see capability decisions
- Log source of each capability value (spec/fallback/hardcoded)
- Track which models use default vs explicit values

### Example Migration: Extended Thinking Support

**Before (Hardcoded)**:
```ruby
# claude_helper.rb
def supports_extended_thinking?(model)
  model.to_s.downcase.include?('sonnet-4.5') ||
  model.to_s.downcase.include?('opus-4')
end
```

**After (SSOT)**:
```ruby
# claude_helper.rb
def supports_extended_thinking?(model)
  result = ModelSpec.supports_extended_thinking?(model, 'anthropic')

  if ENV['EXTRA_LOGGING']
    Rails.logger.debug "[ClaudeHelper] Extended thinking for #{model}: #{result} (source: SSOT)"
  end

  result
end
```

**SSOT Definition** (`model_spec.js`):
```javascript
"claude-sonnet-4.5-20250514": {
  extended_thinking_capability: true,
  thinking_budget_tokens: 20000,
  // ... other capabilities
}
```

### Provider-Specific Patterns

#### OpenAI
- **Responses API**: GPT-5 series uses `/v1/responses` instead of `/v1/chat/completions`
- **Reasoning Models**: o1/o3 series have reasoning_effort parameter
- **Vision**: All GPT-4+ models support vision except text-only variants

#### Anthropic/Claude
- **Extended Thinking**: Claude 4.5/4 series with thinking_budget parameter
- **Prompt Caching**: Claude 3.5+ supports prompt caching for cost optimization
- **Streaming Default**: All Claude models default to streaming enabled

#### Gemini
- **URL Context**: Gemini models can fetch and process URLs directly
- **File API**: Upload files via File API for large documents
- **Multi-Modal**: Native support for images, video, and audio

#### Cohere
- **Command R+**: Enhanced retrieval capabilities
- **Tool Use**: Unique tool calling format with parameter_definitions

#### Mistral
- **Function Calling**: Similar to OpenAI but with provider-specific nuances
- **Streaming**: All models support streaming

#### DeepSeek
- **Context Windows**: Large context windows (up to 64k tokens)
- **Cost Efficiency**: Focus on cost-effective long-context processing

#### Perplexity
- **Native Web Search**: Built-in web search without external tools
- **URL-Only PDFs**: Supports PDF URLs but not file uploads
- **Citations**: Automatic citation generation for search results

#### xAI/Grok
- **Real-Time Data**: Access to X (Twitter) data stream
- **Function Calling**: OpenAI-compatible function format

### Common Capabilities to Centralize

| Capability | Accessor Method | Current Status |
|------------|----------------|----------------|
| Context Window | `context_window(model, provider)` | ✅ Migrated |
| Max Output Tokens | `max_output_tokens(model, provider)` | ✅ Migrated |
| Vision Support | `vision_capability?(model, provider)` | ✅ Migrated |
| Tool Calling | `tool_capability?(model, provider)` | ✅ Migrated |
| Streaming | `supports_streaming?(model, provider)` | ✅ Migrated |
| Extended Thinking | `supports_extended_thinking?(model, provider)` | ✅ Migrated |
| Reasoning Models | `is_reasoning_model(model, provider)` | ✅ Migrated |
| Web Search | `supports_web_search?(model, provider)` | ✅ Migrated |
| PDF Upload | `supports_pdf_upload?(model, provider)` | ✅ Migrated |
| Prompt Caching | `supports_prompt_caching?(model, provider)` | ⏳ Planned |
| Streaming Default | `streaming_default(model, provider)` | ⏳ Planned |
| Tool Call Limit | `max_tool_calls(model, provider)` | ⏳ Planned |

### Benefits of SSOT Approach

1. **Single Source of Truth**: All model capabilities defined in one place
2. **Easier Updates**: Add new models by updating `model_spec.js` only
3. **Consistent Behavior**: Same capability checks across all providers
4. **Reduced Duplication**: Eliminate redundant hardcoded logic
5. **Better Testing**: Unit test capability logic independently of helpers
6. **Easier Debugging**: Centralized audit logging shows capability decisions
7. **Future-Proof**: New providers can reuse existing accessor infrastructure

### Related Documentation

- **Canonical Vocabulary**: `docs_dev/developer/model_spec_vocabulary.md`
- **Anthropic Implementation**: `docs_dev/ruby_service/vendors/anthropic_architecture.md`
- **Model Spec Reference**: `docker/services/ruby/public/js/monadic/model_spec.js`

