# Monadic Chat Internal Documentation

> ⚠️ **Internal Documentation** - This documentation is for Monadic Chat maintainers and contributors only.

## Overview

This is the internal developer documentation for Monadic Chat. It contains:

- Build and test infrastructure details
- Internal architecture notes
- Performance analysis and benchmarks
- Development workflow guides
- Troubleshooting for common issues

## Documentation Structure

### Core Systems
- [Docker Architecture](docker-architecture.md) - Container orchestration details
- [Docker Build Caching](docker-build-caching.md) - Install options, smart caching, auto-restart
- [Logging](logging.md) - Debug and trace logging configuration

### Development Workflow
- [Common Issues](common-issues.md) - Troubleshooting guide
- [Testing](test_runner.md) - Unified test runner documentation

### Feature Documentation
- [Auto Forge Internals](auto_forge_internals.md) - Artifact Builder architecture
- [TTS Prefetch Optimization](tts_prefetch_optimization.md) - Text-to-Speech performance
- [SSOT Normalization](ssot_normalization_and_accessors.md) - Model spec normalization

### API & Integration
- [External APIs](external_apis/) - Third-party API integration guides
- [Python Service](python_service/) - Python Flask service documentation

## Quick Links

- [Public Documentation](/docs/) - User-facing documentation  
- [GitHub Repository](https://github.com/yohasebe/monadic-chat)

## Note

For user-facing documentation, see the [public docs](/docs/). The information here is intended for internal development use only.
