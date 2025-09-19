# ModelSpecUtils Extension Architecture

## Current State Analysis

### What We Have
1. **ModelSpecUtils Module**: Basic utility functions for reading model_spec.js
2. **model_spec.js**: Central source of truth for model capabilities
3. **Partial Dynamic Loading**: Some methods already use ModelSpecUtils

### Current Issues
1. **Hardcoded Model Names**: Still present in various helper files
2. **Special Case Logic**: Scattered across different providers
3. **Inconsistent Model Selection**: Different approaches per provider
4. **Manual Updates Required**: When new models are added

## Proposed Architecture

### Phase 1: Core Infrastructure (Safe)
Create foundation without breaking existing functionality:

#### 1.1 Enhanced ModelSpecUtils Methods
```ruby
module ModelSpecUtils
  # Provider-specific model selection strategies
  def get_provider_strategy(provider)
    # Returns selection strategy: :first, :latest, :most_capable, :custom
  end
  
  # Get model by capability requirements
  def find_model_by_capabilities(provider, required_caps, optional_caps = [])
    # Returns best matching model based on requirements
  end
  
  # Model version comparison
  def compare_model_versions(model1, model2)
    # Returns -1, 0, 1 for version comparison
  end
  
  # Get latest model version for a base model
  def get_latest_version(base_model_name)
    # Returns latest dated version or base if no versions
  end
end
```

#### 1.2 Provider Configuration Registry
```ruby
module ProviderConfig
  PROVIDER_DEFAULTS = {
    "openai" => {
      strategy: :latest,
      fallback_chain: ["gpt-4.1-mini", "gpt-4o-mini"],
      special_cases: {
        vision: :auto_detect,
        reasoning: :explicit_flag
      }
    },
    "claude" => {
      strategy: :first,
      fallback_chain: ["claude-3.5-sonnet-v4-20250805"],
      special_cases: {
        reasoning: :minimal_effort,
        batch_processing: true
      }
    },
    # ... other providers
  }
end
```

### Phase 2: Migration Strategy (Medium Risk)

#### 2.1 Helper Migration Pattern
Each helper gets a standard interface:

```ruby
module GeminiHelper
  def default_model
    @default_model ||= ModelSpecUtils.get_default_model(
      "gemini",
      requirements: { tool_capability: true }
    )
  end
  
  def vision_model
    @vision_model ||= ModelSpecUtils.get_vision_model("gemini") ||
                      default_model
  end
  
  def reasoning_model
    @reasoning_model ||= ModelSpecUtils.find_model_by_capabilities(
      "gemini",
      required_caps: [:reasoning],
      optional_caps: [:tool_capability]
    )
  end
end
```

#### 2.2 Gradual Migration Path
1. **Add new methods alongside existing** (no breaking changes)
2. **Update one provider at a time** with comprehensive testing
3. **Deprecate old methods** after verification
4. **Remove deprecated code** in final phase

### Phase 3: Advanced Features (Future)

#### 3.1 Dynamic Model Discovery
```ruby
class ModelDiscovery
  def self.scan_for_new_models
    # Periodically check model_spec.js for updates
    # Alert when new models detected
    # Suggest configuration updates
  end
end
```

#### 3.2 Capability-Based Routing
```ruby
class ModelRouter
  def route_request(request_type, provider)
    case request_type
    when :code_execution
      find_best_code_model(provider)
    when :image_generation
      find_best_image_model(provider)
    when :reasoning_task
      find_best_reasoning_model(provider)
    end
  end
end
```

## Implementation Plan

### Stage 1: Foundation (Current Sprint)
- [x] Create test suite for ModelSpecUtils
- [ ] Enhance ModelSpecUtils with new methods
- [ ] Add provider configuration registry
- [ ] Create migration helper module

### Stage 2: Provider Migration (Next Sprint)
Priority order based on risk assessment:
1. **Perplexity** - Simplest, no tools (Low risk)
2. **Mistral** - Standard implementation (Low risk)
3. **DeepSeek** - Has special schema handling (Medium risk)
4. **Cohere** - Reasoning model handling (Medium risk)
5. **Grok** - Live search features (Medium risk)
6. **Gemini** - Vision/endpoint switching (High risk)
7. **Claude** - Batch processing logic (High risk)
8. **OpenAI** - Most complex, many models (High risk)

### Stage 3: Validation & Cleanup
- [ ] Comprehensive integration testing
- [ ] Performance benchmarking
- [ ] Deprecation notices
- [ ] Documentation update
- [ ] Final cleanup

## Testing Strategy

### Unit Tests
```ruby
RSpec.describe ModelSpecUtils do
  describe ".find_model_by_capabilities" do
    it "returns model matching all required capabilities"
    it "prioritizes models with optional capabilities"
    it "falls back to default when no match"
    it "handles missing provider gracefully"
  end
end
```

### Integration Tests
```ruby
RSpec.describe "Provider Model Selection" do
  providers.each do |provider|
    it "selects appropriate default model"
    it "handles vision requests correctly"
    it "falls back gracefully on errors"
    it "maintains backward compatibility"
  end
end
```

### Regression Tests
- Ensure all existing apps continue to work
- Verify model selection produces same results
- Check performance is not degraded

## Risk Mitigation

### Rollback Plan
1. Each change is feature-flagged
2. Old code remains until fully validated
3. Database of working model combinations maintained
4. Automated rollback on test failure

### Monitoring
- Log all model selections with reasons
- Track success/failure rates per model
- Alert on unexpected model switches
- Performance metrics for selection logic

## Success Criteria

1. **Zero Breaking Changes**: All existing functionality preserved
2. **Improved Maintainability**: Single source of truth for models
3. **Future-Proof**: Easy to add new models/providers
4. **Better Testing**: Comprehensive test coverage
5. **Documentation**: Clear migration guide for contributors

## Timeline Estimate

- **Phase 1**: 2-3 days (Foundation)
- **Phase 2**: 5-7 days (Migration, 1 day per provider)
- **Phase 3**: 2-3 days (Validation & Cleanup)
- **Total**: ~2 weeks for complete migration

## Next Immediate Steps

1. Create ModelSpecUtils test file
2. Implement enhanced methods in ModelSpecUtils
3. Test with simplest provider (Perplexity)
4. Document lessons learned
5. Proceed with gradual migration