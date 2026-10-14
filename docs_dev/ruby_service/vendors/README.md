# Vendor-Specific Documentation

Each AI provider has a helper module in `docker/services/ruby/lib/monadic/adapters/vendors/`. The documents here describe the request, streaming, tool-call and error behavior of individual helpers.

## Contents

- [Anthropic/Claude Architecture](anthropic_architecture.md) — beta headers, thinking, limits, retries and streaming
- [DeepSeek Architecture](deepseek_architecture.md) — thinking, images, tool calls, terminal tools and DSML parsing

## Related Documentation

- [SSOT Normalization](../../ssot_normalization_and_accessors.md)
- [Model Spec Vocabulary](../../developer/model_spec_vocabulary.md)
