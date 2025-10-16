# Monadic Chat Internal Documentation

## Overview

This is the internal developer documentation for Monadic Chat. It contains technical details about the implementation, architecture, and development workflow that are not relevant to end users.

**For user-facing documentation**, see the [Public Documentation](https://yohasebe.github.io/monadic-chat/).

## 📚 Documentation Structure

### 🚀 Getting Started
New to the codebase? Start here:
- **[Debug Mode & Local Docs](server-debug-mode.md)** - How to run the development server and access local documentation
- **[Docs Link Checker](docs-link-checker.md)** - Validate all documentation links to prevent 404 errors
- **[Common Issues](common-issues.md)** - Troubleshooting guide for common development problems

### 🏗️ Architecture
High-level system design and component relationships:
- **[Docker Architecture](docker-architecture.md)** - Container orchestration and service configuration
- **[Docker Build Caching](docker-build-caching.md)** - Build optimization and caching strategies
- **[Frontend Architecture](frontend/)** - JavaScript architecture and UI components

### 🔧 Core Systems
Implementation details of key features:
- **[Logging](logging.md)** - Debug and trace logging configuration
- **[Error Handling](error_handling.md)** - Error detection and recovery strategies
- **[WebSocket Progress Broadcasting](websocket_progress_broadcasting.md)** - Real-time progress updates
- **[Token Counting](token_counting.md)** - Token usage tracking and optimization
- **[Type Conversion Policy](type_conversion_policy.md)** - Data type handling conventions

### 🧪 Testing & Quality
Test infrastructure and procedures:
- **[Test Runner](test_runner.md)** - Unified test runner documentation
- **[Test Quick Reference](test_quickref.md)** - Quick reference for running tests
- **[Testing Guide](testing.md)** - Testing philosophy and best practices

### 📦 Feature Documentation
In-depth documentation of specific features:
- **[Auto Forge Internals](auto_forge_internals.md)** - Artifact Builder architecture
- **[SSOT Normalization](ssot_normalization_and_accessors.md)** - Model specification normalization
- **[TTS Prefetch Optimization](tts_prefetch_optimization.md)** - Text-to-Speech performance optimization
- **[PDF Registry & Hybrid](pdf_registry_and_hybrid.md)** - PDF document storage abstraction

### 💻 Frontend & ⚙️ Backend
Component-specific documentation:
- **[Frontend](frontend/)** - JavaScript modules and UI components
- **[Backend](ruby_service/)** - Ruby service implementation
- **[Python Service](python_service/)** - Python Flask service
- **[MDSL](mdsl/)** - Monadic DSL documentation

## 🔄 Documentation Guidelines

### Internal vs External Documentation

**Use Internal docs (`docs_dev/`) for:**
- Implementation details and architecture decisions
- Internal APIs and data flows
- Development workflows and debugging
- Test procedures and infrastructure

**Use External docs (`docs/`) for:**
- User-facing features and functionality
- Installation and setup instructions
- Basic usage guides and tutorials
- Public API documentation
- User troubleshooting guides

### Keeping Documentation Current

During the Beta period (pre-1.0), we follow these principles:
- **No outdated information** - Always replace old docs with current information
- **Active maintenance** - Update docs as you change code
- **Single source of truth** - Each topic should have one authoritative document

## 🔍 Local Documentation Access

When running in debug mode (`rake server:debug`), both internal and external documentation are available locally:
- Internal docs: http://localhost:4567/docs_dev/
- External docs: http://localhost:4567/docs/

See **[Debug Mode & Local Docs](server-debug-mode.md)** for details.

## 📖 Quick Links

- [Public Documentation](https://yohasebe.github.io/monadic-chat/) - User-facing docs
- [GitHub Repository](https://github.com/yohasebe/monadic-chat) - Source code
- [Common Issues](common-issues.md) - Troubleshooting for developers
- [Test Runner](test_runner.md) - How to run tests

## Note

This documentation is in active development alongside the codebase. If you find any discrepancies between the docs and the code, the code is the source of truth. Please update the docs to match!
