# Technical Debt and Future Improvements

## Overview

This document tracks known technical debt, architectural improvements, and future enhancements for Monadic Chat. Items are organized by category and priority.

## Type System and Data Flow

### High Priority

#### Boolean Feature Flags Type Consistency
- **Status**: ✅ RESOLVED (2025-01)
- **Issue**: Boolean values were converted to strings, causing "false" to evaluate as truthy
- **Solution**: Implemented type preservation in `websocket.rb` and `toBool` helper in JavaScript
- **Files**: `websocket.rb`, `utilities.js`, `monadic.js`, `websocket.js`

### Medium Priority

#### Numeric Parameter Type Preservation
- **Current State**: `temperature`, `context_size`, `max_tokens` are stringified
- **Impact**: Low (JavaScript type coercion handles most cases)
- **Proposed**: Add to type-preservation list in `prepare_apps_data`
- **Risk**: Low
- **Dependencies**: Type conversion policy documentation

#### JSDoc Type Annotations
- **Scope**: All JavaScript public APIs
- **Benefits**: IDE support, self-documentation, TypeScript foundation
- **Files**: `utilities.js`, `monadic.js`, `websocket.js`, `model_spec.js`
- **Approach**: Incremental, starting with critical modules

#### Runtime Type Validation (Development Mode)
- **Goal**: Catch type errors during development
- **Approach**: Conditional validation based on `DEVELOPMENT_MODE` flag
- **Libraries**: Custom validators or lightweight schema validation
- **Benefit**: Early error detection without production overhead

### Low Priority

#### TypeScript Migration
- **Scope**: Gradual migration of JavaScript codebase
- **Approach**:
  - Start with `.d.ts` type definitions
  - Migrate new modules first
  - Incremental conversion of existing modules
- **Benefits**: Compile-time type safety, better refactoring
- **Challenges**: Large codebase, build complexity, team training

#### Comprehensive Runtime Validation
- **Scope**: All data boundaries (WebSocket, API, user input)
- **Libraries**: Zod, io-ts, or Joi
- **Benefits**: Data corruption prevention, better error messages
- **Overhead**: Performance impact in production

## Session Management and State Isolation

### High Priority

#### Cross-App Message Leakage
- **Status**: ✅ RESOLVED (2025-01)
- **Issue**: Messages not filtered by `app_name`, causing context contamination
- **Solution**: Added `app_name` field to all messages, filter on load
- **Files**: `websocket.rb`

#### Instance Variable Race Conditions
- **Status**: ✅ RESOLVED (2025-01)
- **Issue**: `@context` shared across sessions causing data contamination
- **Solution**: Removed `@context` usage, switched to pure functions
- **Files**: `mermaid_grapher_tools.rb`, `auto_forge_tools.rb`

### Medium Priority

#### Session State Management Formalization
- **Goal**: Establish clear guidelines for session-specific vs. app-global state
- **Current**: Documented in `app_isolation_and_session_safety.md`
- **Proposed**:
  - Static analysis to detect instance variable usage in tool methods
  - Runtime assertion framework for development
  - Code review checklist enforcement

#### Thread Safety Audit
- **Scope**: Review all shared state access patterns
- **Focus Areas**:
  - Global constants (APPS, CONFIG)
  - Class-level caching
  - Database connection pools
- **Tools**: Thread safety analyzer, concurrent request testing

## Testing Infrastructure

### High Priority

#### App Switching Integration Tests
- **Status**: ✅ IMPLEMENTED (2025-01)
- **Coverage**: Feature flags, message filtering, type consistency
- **File**: `spec/integration/app_switching_integration_spec.rb`

### Medium Priority

#### Property-Based Testing
- **Goal**: Verify invariants across all inputs
- **Use Cases**:
  - Type preservation through serialization
  - Session isolation guarantees
  - Feature flag consistency
- **Library**: RSpec with custom property generators

#### Contract Testing
- **Goal**: Verify WebSocket protocol contracts
- **Scope**:
  - Client-server message formats
  - Type contracts for all messages
  - Backward compatibility guarantees
- **Tools**: Pact or custom contract framework

#### Visual Regression Testing
- **Goal**: Catch UI changes from feature flag bugs
- **Scope**: UI elements controlled by feature flags
- **Tools**: Percy, BackstopJS, or Playwright screenshots
- **Focus**: App switching UI states

### Low Priority

#### Mutation Testing
- **Goal**: Verify test suite effectiveness
- **Scope**: Critical business logic (session isolation, type conversion)
- **Tools**: Mutant (Ruby), Stryker (JavaScript)

#### Chaos Engineering
- **Goal**: Test system resilience
- **Scenarios**:
  - Concurrent app switching
  - Race condition simulation
  - Type corruption injection
- **Environment**: Staging only

## Performance and Optimization

### Medium Priority

#### WebSocket Message Optimization
- **Current**: Full app data sent on each load
- **Proposed**:
  - Delta updates for app switching
  - Client-side caching with invalidation
  - Compression for large tool definitions
- **Benefit**: Reduced bandwidth, faster app switching

#### Type Conversion Caching
- **Observation**: `prepare_apps_data` called frequently
- **Proposed**: Cache result with invalidation on app reload
- **Benefit**: Reduced CPU usage, faster response times
- **Risk**: Cache invalidation complexity

#### Lazy Loading for App Definitions
- **Current**: All apps loaded at startup
- **Proposed**: Load apps on-demand
- **Benefit**: Faster startup, lower memory footprint
- **Challenge**: Complex app dependency management

## Code Quality and Maintainability

### Medium Priority

#### Linting Rule Enforcement
- **Current**: RuboCop for Ruby, ESLint for JavaScript
- **Proposed**: Add custom rules for:
  - Instance variable usage in tool methods
  - Type annotation requirements
  - Session isolation patterns
- **Integration**: Pre-commit hooks, CI/CD pipeline

#### Code Complexity Metrics
- **Tools**: CodeClimate, SimpleCov, Flog
- **Thresholds**:
  - Cyclomatic complexity < 10
  - Method length < 25 lines
  - Class length < 200 lines
- **Exceptions**: Generated code, DSL methods

#### Documentation Coverage
- **Goal**: 100% public API documentation
- **Tools**: YARD (Ruby), JSDoc (JavaScript)
- **Metrics**: Track undocumented methods, missing type annotations
- **Process**: Documentation requirements in PR template

### Low Priority

#### Monorepo Restructuring
- **Current**: Docker services in nested directories
- **Proposed**:
  - Clearer separation of concerns
  - Independent versioning for components
  - Shared libraries as packages
- **Benefit**: Better modularity, easier testing
- **Challenge**: Migration complexity

#### Dependency Audit
- **Goal**: Reduce dependency count, update outdated packages
- **Focus**:
  - Remove unused dependencies
  - Update packages with security vulnerabilities
  - Replace heavy dependencies with lighter alternatives
- **Tools**: Bundler-audit, npm-audit, Dependabot

## Architecture and Design

### Medium Priority

#### Event-Driven Architecture
- **Current**: Direct method calls, tight coupling
- **Proposed**: Event bus for app lifecycle events
- **Events**:
  - App switched
  - Feature flag changed
  - Session initialized/destroyed
- **Benefits**: Loose coupling, easier testing, plugin system foundation

#### Plugin System Formalization
- **Current**: Informal plugin structure
- **Proposed**:
  - Plugin manifest format
  - Dependency declaration
  - Version compatibility checking
- **Benefits**: Third-party extension support, better isolation

#### API Versioning Strategy
- **Current**: No explicit versioning
- **Proposed**:
  - WebSocket protocol versioning
  - Backward compatibility policy
  - Deprecation process
- **Benefit**: Smoother upgrades, clearer contracts

### Low Priority

#### Microservices Consideration
- **Current**: Monolithic Ruby service
- **Evaluation Criteria**:
  - Independent scaling needs
  - Team structure
  - Deployment complexity
- **Components to Consider**:
  - PDF processing service
  - Code execution sandbox
  - Web search service
- **Note**: Only if clear benefits outweigh complexity

#### GraphQL API
- **Alternative to**: REST-like WebSocket messages
- **Benefits**:
  - Strong typing
  - Client-defined queries
  - Introspection
- **Challenges**:
  - Learning curve
  - WebSocket integration
  - Existing client code migration

## Security and Reliability

### High Priority

#### Input Validation Framework
- **Current**: Ad-hoc validation in various places
- **Proposed**: Centralized validation with schema definitions
- **Scope**:
  - User input (messages, settings)
  - File uploads
  - API parameters
- **Tools**: JSON Schema, custom validators

### Medium Priority

#### Rate Limiting
- **Scope**: API calls, message sending, file uploads
- **Strategy**: Per-user, per-app quotas
- **Implementation**: Rack middleware, Redis-backed
- **Benefit**: Abuse prevention, cost control

#### Audit Logging
- **Events**:
  - App switching
  - Settings changes
  - File operations
  - Security events
- **Storage**: Structured logs, queryable
- **Retention**: Configurable by deployment

#### Error Recovery Strategies
- **Current**: Basic error pattern detection
- **Proposed**:
  - Exponential backoff for retries
  - Circuit breaker pattern
  - Graceful degradation
- **Scope**: External API calls, Docker operations

### Low Priority

#### End-to-End Encryption
- **Scope**: WebSocket messages, stored data
- **Use Case**: Enterprise deployments
- **Approach**: TLS for transport, at-rest encryption option
- **Complexity**: Key management, performance impact

#### Penetration Testing
- **Goal**: Identify security vulnerabilities
- **Focus Areas**:
  - Docker escape attempts
  - Code injection vectors
  - Session hijacking
- **Frequency**: Annual or after major changes

## Developer Experience

### Medium Priority

#### Development Environment Improvements
- **Hot Reload**: Automatic Ruby/JavaScript reload on changes
- **Debug Tools**: Better logging, debugging UI
- **Test Helpers**: Shared test utilities, factories
- **Documentation**: Developer onboarding guide

#### CI/CD Pipeline Enhancement
- **Parallel Testing**: Speed up test suite
- **Deployment Automation**: One-click releases
- **Preview Environments**: PR-based staging
- **Rollback Strategy**: Quick revert on issues

#### Error Messages and Debugging
- **Goal**: Better error messages for developers and users
- **Scope**:
  - Type mismatch errors with context
  - Stack traces with source maps
  - Suggested fixes for common errors
- **Tools**: Better error classes, custom inspectors

### Low Priority

#### Developer Dashboard
- **Features**:
  - App metrics (usage, errors)
  - Type consistency reports
  - Performance profiles
  - Test coverage visualization
- **Goal**: Visibility into system health

#### Code Generation Tools
- **Use Cases**:
  - MDSL app scaffolding
  - Test boilerplate
  - Type definition generation
- **Benefit**: Consistency, reduced boilerplate

## Migration and Upgrade Strategies

### General Principles

1. **Backward Compatibility**: Maintain for at least one major version
2. **Feature Flags**: Use for gradual rollouts
3. **Data Migration**: Automated scripts with rollback capability
4. **Documentation**: Clear upgrade guides for each change
5. **Testing**: Comprehensive testing before production

### Specific Migration Plans

#### Type System Migration
- Phase 1: Add type preservation for critical parameters (✅ DONE)
- Phase 2: JSDoc annotations for public APIs
- Phase 3: Development-time validation
- Phase 4: Consider TypeScript for new code
- Phase 5: Gradual TypeScript migration

#### Testing Infrastructure
- Phase 1: Integration tests for critical paths (✅ DONE)
- Phase 2: Property-based tests
- Phase 3: Contract tests
- Phase 4: Visual regression tests

#### Architecture Evolution
- Phase 1: Event bus introduction
- Phase 2: Plugin system formalization
- Phase 3: API versioning
- Phase 4: Evaluate microservices (if needed)

## Tracking and Review

### Metrics to Track
- Type error incidents in production
- Session isolation violations
- Test coverage (line, branch, mutation)
- Technical debt ratio (new vs. old code)
- MTTR (Mean Time To Repair)

### Review Process
- Quarterly: Review this document, update priorities
- After major incidents: Add learnings to technical debt
- During planning: Consider items for upcoming work
- Annual: Major architectural review

## Notes

- This document should be updated as issues are resolved or new debt is identified
- Each item should link to relevant documentation, issues, or PRs
- Priority levels are guidelines, not strict requirements
- Consider risk, impact, and effort when prioritizing work

## References

- `docs_dev/type_conversion_policy.md` - Type system documentation
- `docs_dev/app_isolation_and_session_safety.md` - Session safety
- `docs_dev/common-issues.md` - Known issues and solutions
- `docs/developer/testing_guide.md` - Testing approach
