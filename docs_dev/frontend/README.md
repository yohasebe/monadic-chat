# Frontend Documentation

This section contains internal documentation for Monadic Chat's frontend architecture and implementation details.

## Contents

### Testing
- [No Mock Testing](no_mock/) - Frontend testing philosophy and implementation guide
  - Comprehensive explanation of why no-mock approach is preferred over traditional mock-based testing
  - Detailed comparison of mock-based vs no-mock patterns with code examples
  - Best practices, test utilities, and migration guide
  - Current status: 24 tests passing across 3 test suites

### UI Architecture
- [UI State Synchronization](ui_synchronization.md) - Known synchronization issues and solutions
  - Model selection badge update timing issues
  - Event propagation conflicts between `loadParams()` and reasoning UI
  - Best practices for explicit state updates and event handling

## Overview

The frontend of Monadic Chat is built with vanilla JavaScript and uses WebSocket for real-time communication with the Ruby backend. Key architectural components include:

- **WebSocket Client** (`docker/services/ruby/public/js/monadic/websocket.js`) - Real-time bidirectional communication
- **UI Components** (`docker/services/ruby/public/js/monadic/ui/`) - Modular UI building blocks
- **Shared Components** (`docker/services/ruby/public/js/monadic/shared/`) - Common utilities and helpers
- **App-Specific Modules** (`docker/services/ruby/public/js/monadic/apps/`) - Application-specific frontend logic
- **Model Specification** (`docker/services/ruby/public/js/monadic/model_spec.js`) - SSOT for model capabilities

## Related Documentation

For frontend-related topics covered elsewhere:
- [JS Console](../js-console.md) - JavaScript console logging modes
- [External Libraries](../external-libs.md) - Vendor asset management
- [SSOT Normalization](../ssot_normalization_and_accessors.md) - Model capability vocabulary

See also:
- `docs_dev/developer/code_structure.md` - Public developer reference for code organization
