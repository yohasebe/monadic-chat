# Ruby Service Documentation

This section contains internal documentation for Monadic Chat's Ruby backend service.

## Contents

### Architecture
- [Monadic Architecture](monadic_architecture.md) - Core service architecture overview
- [ModelSpec Extension Architecture](modelspec_extension_architecture.md) - Model specification extension system

### Development
- [Development Guide](development.md) - Ruby service development workflow
- [Path Handling Guide](path_handling_guide.md) - File path management patterns
- [Streaming Best Practices](streaming_best_practices.md) - Server-Sent Events and streaming implementation

### Features
- [Language Aware Apps](language_aware_apps.md) - Multi-language application support
- [Thinking/Reasoning Display](thinking_reasoning_display.md) - Internal reasoning process visualization

### Testing
- [Testing](testing/) - Ruby service testing documentation

### Apps
- [Apps](apps/) - Application-specific documentation

### Scripts
- [Scripts](scripts/) - Utility scripts documentation

### API Documentation
- [Docs](docs/) - Generated API documentation

## Overview

The Ruby service is the core backend of Monadic Chat, built on Rack and EventMachine. Key components include:

- **Rack Application** (`config.ru`, `lib/monadic.rb`) - HTTP/WebSocket server
- **WebSocket Server** (`lib/monadic/utils/websocket.rb`) - Real-time bidirectional communication
- **Vendor Adapters** (`lib/monadic/adapters/vendors/`) - AI provider integrations
- **MDSL Engine** (`lib/monadic/dsl.rb`) - App definition language processor
- **Applications** (`apps/`) - 20+ specialized chat applications

## Key Technologies

- **Rack** - Web server interface
- **EventMachine** - Event-driven I/O
- **WebSocket** - Real-time communication protocol
- **Docker** - Container orchestration
- **PostgreSQL/PGVector** - Vector database for embeddings

## Related Documentation

Core systems:
- [Logging](/logging.md)
- [Error Handling](/error_handling.md)
- [WebSocket Progress Broadcasting](/websocket_progress_broadcasting.md)
- [Token Counting](/token_counting.md)
- [Type Conversion Policy](/type_conversion_policy.md)

See also:
- `docs_dev/developer/code_structure.md` - Public code organization reference
- `docs_dev/developer/development_workflow.md` - Development best practices
