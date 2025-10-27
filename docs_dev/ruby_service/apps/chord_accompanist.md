# Chord Accompanist App

This document explains the Chord Accompanist implementation, architecture decisions, and design evolution.

## Current Implementation

- **ABC Notation Normalization**: Normalised on both Ruby and JS sides (HTML decode, unicode dashes/quotes → ASCII, repeated blank lines collapsed, brackets cleaned)
- **Validation**: Uses ABCJS inside Selenium, mirroring the Mermaid Grapher approach
- **Workflow**: `validate_abc_syntax` → `analyze_abc_error` (if needed) → respond
- **Implemented Tools**:
  - `validate_chord_progression`: Check music theory rules
  - `validate_abc_syntax`: Verify ABC notation syntax using ABCJS
  - `analyze_abc_error`: Analyze validation errors and suggest fixes

## Architecture Evolution: Planned vs Actual Implementation

### Original Problem: Infinite Validation Loops

Early implementations suffered from infinite validation loops when ABC notation generation failed.

**Failure Pattern**:
```
1. LLM generates ABC notation
2. Validation fails (syntax error)
3. LLM tries to fix → generates new ABC
4. Validation fails again (different error)
5. Loop continues indefinitely
```

**Root Cause**: Single-agent architecture with LLM handling both generation and validation in one conversation turn. Without clear separation of concerns, fixes often introduced new errors.

### Proposed Multi-Agent Solution (Not Implemented)

**Original Plan**: Eliminate loops by restructuring workflow into discrete stages handled by specialized agents.

**Planned 5-Agent Pipeline**:
```
User Input → RequirementsAgent → requirements.json
          → ProgressionAgent → progression.json
          → ArrangementAgent → draft.abc
          → ValidationAgent → validated ABC
          → SummaryAgent → User
```

**Why Not Implemented**:
- **Complexity vs Benefit**: 5-agent pipeline introduced significant overhead
- **Latency**: Multiple sequential LLM calls increase response time
- **Debugging Difficulty**: Error tracking across agent boundaries
- **Over-Engineering**: Simpler tool-based approach proved sufficient

### Actual Implementation: Simpler Tool-Based Approach

**Current Single-Agent Workflow**:
```
1. LLM generates chord progression
2. LLM calls validate_chord_progression tool
3. If valid, LLM generates ABC notation
4. LLM calls validate_abc_syntax tool
5. If errors, LLM calls analyze_abc_error tool (max 3 attempts)
6. Success or explain failure to user
```

**Benefits**:
- ✅ Lower latency (single conversation turn)
- ✅ Easier to debug (all logic in one context)
- ✅ Explicit retry limit prevents infinite loops
- ✅ Sufficient for current use cases

## Design Lessons Learned

### 1. Start Simple, Add Complexity Only When Needed

**Anti-Pattern**: Design elaborate multi-agent architecture upfront

**Better Approach**: Start with simplest solution that works, add agents only when complexity justifies overhead

**Applied**: Started with tool-based validation, added targeted fixes instead of full agent pipeline

### 2. Explicit Limits Prevent Infinite Loops

**Problem**: LLM retry logic can loop indefinitely on validation failures

**Solution**: Hard limits on retry attempts (max 3) + explicit "should_retry" flag in tool responses

### 3. Deterministic Validation Should Be Fast

**Design Principle**: Validation tools execute quickly without additional LLM calls

```ruby
# ✅ Good: Fast, deterministic ABCJS validation
def validate_abc_syntax(abc_code:)
  # Uses ABCJS JavaScript library via Selenium
  # Returns immediate result
end
```

## Related Files

- **Implementation**: `docker/services/ruby/apps/chord_accompanist/chord_accompanist_tools.rb`
- **MDSL Definitions**: `docker/services/ruby/apps/chord_accompanist/chord_accompanist_*.mdsl`
- **ABC Rendering**: `docker/services/ruby/public/js/monadic/abc_renderer.js`
