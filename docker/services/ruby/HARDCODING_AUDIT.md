# Hardcoding Audit Report
Generated: 2025-08-28

## Overview
This document identifies all hardcoded model names and provider-specific logic in the codebase that should be migrated to dynamic configuration.

## Risk Assessment Scale
- 🔴 **High Risk**: Core functionality depends on hardcoded values
- 🟡 **Medium Risk**: Feature-specific hardcoding that could break with model updates
- 🟢 **Low Risk**: Cosmetic or fallback values

## OpenAI Helper (lib/monadic/adapters/vendors/openai_helper.rb)

### 🔴 High Risk Hardcoding

#### GPT-5 Streaming Duplicate Fix (Lines 1825-1869)
```ruby
# Lines 1825, 1830, 1869
if current_model.to_s.include?("gpt-5") || 
   current_model.to_s.include?("gpt-4.1") || 
   current_model.to_s.include?("chatgpt-4o")
```
**Impact**: Streaming responses show duplicate characters if not handled
**Recommendation**: Move to model_spec.js with `streaming_duplicate_fix: true` flag

#### Responses API Model Detection (Lines 61, 95, 111)
```ruby
"gpt-5"  # Hardcoded in RESPONSES_API_MODELS array
```
**Impact**: New GPT-5 variants won't use Responses API automatically
**Recommendation**: Use model capability flags in model_spec.js

#### Verbosity Support (Lines 488, 1145, 1163)
```ruby
if verbosity && model.to_s.include?("gpt-5")
```
**Impact**: Verbosity feature only works for GPT-5
**Recommendation**: Add `supports_verbosity: true` to model spec

### 🟡 Medium Risk Hardcoding

#### Default Model Lists
```ruby
# Various arrays throughout the file
RESPONSES_API_MODELS = ["gpt-5", ...]
RESPONSES_API_WEBSEARCH_MODELS = ["gpt-5", ...]
```
**Impact**: Manual updates required for new models
**Recommendation**: Generate from model_spec.js at runtime

## Claude Helper (lib/monadic/adapters/vendors/claude_helper.rb)

### 🔴 High Risk Hardcoding

#### Thinking Model Detection (Line 490)
```ruby
thinking_models = ["claude-opus-4-20250514", "claude-sonnet-4-20250514"]
```
**Impact**: New thinking models won't be recognized
**Recommendation**: Use ModelSpecUtils.is_thinking_model?

#### Model Arrays (Lines 93-109)
```ruby
"claude-3-opus-20240229",
"claude-3-5-sonnet-20241022",
"claude-opus-4-20250514",
"claude-sonnet-4-20250514"
```
**Impact**: Model availability checks fail for new models
**Recommendation**: Migrate to model_spec.js

### 🟡 Medium Risk Hardcoding

#### Default Model (Line 152)
```ruby
def send_query(options, model: "claude-3-5-sonnet-20241022")
```
**Impact**: Default model outdated when newer versions release
**Recommendation**: Use ModelSpecUtils.get_default_model("claude")

#### Model Name Patterns (Lines 379-382)
```ruby
"claude-opus-4",
"claude-sonnet-4",
"claude-3-7-sonnet",
"claude-3-5-sonnet"
```
**Impact**: Pattern matching for model families
**Recommendation**: Add model family detection to ModelSpecUtils

## Gemini Helper (lib/monadic/adapters/vendors/gemini_helper.rb)

### 🟢 Low Risk (Already Improved)
- Most hardcoding removed in recent updates
- IMAGE_GENERATION_MODEL constant acceptable (separate API)

## Migration Strategy

### Phase 1: Document and Test (✅ Current Phase)
1. Create comprehensive tests for affected areas
2. Document all hardcoding locations
3. Verify current behavior

### Phase 2: Extend ModelSpecUtils
```ruby
# Proposed additions to ModelSpecUtils
module ModelSpecUtils
  def self.supports_feature?(model, feature)
    spec = load_model_spec[model]
    spec && spec[feature] == true
  end
  
  def self.get_models_with_capability(provider, capability)
    # Return all models with specific capability
  end
end
```

### Phase 3: Gradual Migration
1. Start with low-risk constants
2. Add feature flags to model_spec.js
3. Replace hardcoding with dynamic lookups
4. Test thoroughly between each change

### Phase 4: Validation
1. Run all tests
2. Manual testing of affected features
3. Performance comparison

## Tracking Progress

### Completed
- [x] Gemini helper hardcoding reduction
- [x] Cohere helper partial improvement
- [x] Grok helper partial improvement

### Pending
- [ ] OpenAI GPT-5 streaming logic
- [ ] OpenAI Responses API model detection
- [ ] Claude thinking model detection
- [ ] Claude default model
- [ ] Provider model arrays

## Test Coverage Requirements

Before removing any hardcoding, ensure tests exist for:
1. Streaming response handling (especially GPT-5)
2. Responses API vs Chat Completions API selection
3. Thinking/reasoning model detection
4. Default model selection
5. Feature capability detection

## Notes
- Some hardcoding may be intentional for performance
- Provider APIs may have undocumented requirements
- Always test with actual API calls, not just unit tests
- Keep fallbacks for when model_spec.js is unavailable