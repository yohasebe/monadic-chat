# Developer Notes

## System Architecture Improvements (August 2025)

### Unified Error Handling System
- **Implementation**: Centralized error handler at `/lib/monadic/utils/error_handler.rb`
- **Format**: `Error: [Category] - Message. Suggestion (Code: XXX)`
- **Categories**: API Error, Invalid Input, Configuration Error, Tool Error, Network Error, etc.
- **Smart Detection**: Automatically categorizes errors and provides actionable suggestions
- **Migration**: Progressive - Jupyter and Grok helpers updated as examples
- **Testing**: 37 comprehensive test cases covering all error scenarios

### MathJax Header Rendering Fix
- **Issue**: Math expressions in headers (h1-h6) not rendering
- **Solution**: Modified `mathjax-config.js` to explicitly process header tags
- **Fallback**: Added prompt guidance to use bold text for math-containing titles

### Provider-Specific Limitations

#### Grok (xAI)
- Cannot use structured output (`monadic: true`) with tool execution
- Jupyter Notebook requires post-processing to fix filename issues
- Recommendation: Use for simple tool tasks, not complex workflows

#### Gemini 2.5
- Trade-off: Cannot have both function calling and structured JSON simultaneously
- Use `reasoning_effort: "low"` for function calling apps (better balance)
- Remove `reasoning_effort` for monadic mode apps
- Gemini 2.5 Flash recommended for cost/performance balance
- **Google Search Grounding**: Native support with metadata display
  - Shows search queries, grounding chunks, and search entry points
  - Automatically appended to response when web search is enabled

#### Cohere Command-A
- Critical: Cannot chain multiple tool calls
- Single tool execution per request only
- Not suitable for Jupyter Notebook or complex workflows

## Testing Infrastructure

### Test Organization
```bash
# Navigate to Ruby service directory
cd docker/services/ruby

# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/e2e/code_interpreter_spec.rb

# Run with debug output
EXTRA_LOGGING=true bundle exec rspec spec/e2e/research_assistant_workflow_spec.rb --format documentation
```

### PostgreSQL Test Configuration
- Test database runs on port 5433 (production uses 5432)
- Auto-starts when running tests with `:integration` tag
- Configuration in `docker/services/pgvector/compose.dev.yml`

### Environment Variables
```bash
POSTGRES_PORT=5433        # Test environment
EXTRA_LOGGING=true       # Verbose logging
DEBUG_TESTS=true         # Test debug mode
E2E_DEBUG=1             # E2E test debugging
```

## JavaScript Architecture

### Session State Management
- Centralized state in `public/js/monadic/session_state.js`
- Event-driven updates with persistence to localStorage
- Backward compatible with global variables

### Patch System
- Patches extend base functionality without modifying originals
- Located in `public/js/monadic/*_patch.js`
- Store original function before overriding

## Application Availability Matrix

| Provider | Chat | Code Interpreter | Jupyter | Research | Voice | Math Tutor |
|----------|------|-----------------|---------|----------|-------|------------|
| OpenAI   | ✅   | ✅              | ✅      | ✅       | ✅    | ✅         |
| Claude   | ✅   | ✅              | ✅      | ✅       | ✅    | ✅         |
| Gemini   | ✅   | ✅              | ✅      | ✅       | ✅    | ✅         |
| Grok     | ✅   | ✅              | ✅*     | ✅       | ✅    | ✅         |
| Cohere   | ✅   | ✅              | ❌      | ✅       | ✅    | ✅         |
| Mistral  | ✅   | ✅              | ❌      | ✅       | ✅    | ✅         |
| Perplexity| ✅  | ✅              | ❌      | ✅       | ✅    | ❌         |
| DeepSeek | ✅   | ✅              | ❌      | ✅       | ✅    | ❌         |
| Ollama   | ✅   | ❌              | ❌      | ❌       | ❌    | ❌         |

*Grok Jupyter has filename display limitations (workaround implemented)

## Development Guidelines

### Error Messages
- Use ErrorHandler for consistent formatting
- Always provide user-actionable suggestions
- Categories help with debugging and support

### Testing Philosophy
- Prefer real implementation tests over mocks
- Test actual behavior, not implementation details
- Include `:integration` tag for Docker-dependent tests

### Code Style
- Follow existing patterns in codebase
- Use existing libraries and utilities
- Minimal comments - code should be self-documenting

### Git Commit Guidelines
- Focus on technical changes
- No attribution to AI assistants
- Clear, concise commit messages

## Current Test Count: 1253 passing tests