# Vendor-Specific Documentation

This directory contains documentation for AI provider integrations in Monadic Chat.

## Contents

- [Anthropic/Claude Architecture](anthropic_architecture.md) - Claude integration design decisions and implementation patterns
  - Hardcoded behavior patterns and their rationale
  - SSOT migration status
  - API request formats and streaming
  - Error handling and performance optimization

## Overview

Each AI provider (OpenAI, Anthropic, Gemini, Mistral, Cohere, DeepSeek, Perplexity, xAI/Grok, Ollama) has a corresponding helper class in `docker/services/ruby/lib/monadic/adapters/vendors/`.

These documents explain:
- **Design Decisions**: Why certain patterns were chosen (e.g., beta feature flags, streaming defaults)
- **Architecture Evolution**: Migration from hardcoded logic to SSOT (Single Source of Truth)
- **Provider-Specific Behavior**: Unique features and constraints of each provider
- **Implementation Patterns**: Common patterns and best practices

## Related Documentation

- [SSOT Normalization](../../ssot_normalization_and_accessors.md) - Single Source of Truth strategy for all providers
- [Model Spec Vocabulary](../../developer/model_spec_vocabulary.md) - Canonical vocabulary for model capabilities
- [Vendor Helpers](../../../docker/services/ruby/lib/monadic/adapters/vendors/) - Implementation code
