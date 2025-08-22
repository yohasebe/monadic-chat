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

#### Claude (Anthropic)
- **Batch Processing**: All tool calls now processed in single API request for better performance
- **Reasoning Effort**: Use `minimal` for function-calling apps (optimal performance)
- **Thinking Budget**: Minimum 1024 tokens required for `minimal` reasoning mode
- **Jupyter Notebook**: Requires `monadic: false` for proper tool execution
- **Monadic Mode Conflicts**:
  - Thinking blocks interfere with JSON structure
  - Responses wrapped in markdown code blocks (```json)
  - Tool execution breaks JSON formatting continuity
- **Best Practices**: 
  - Set `reasoning_effort: "minimal"` for all tool-heavy apps
  - Use `reasoning_effort: "none"` only when thinking is completely unnecessary
  - Batch processing improves Jupyter Notebook cell addition significantly
  - Always use `monadic: false` for tool-heavy applications

#### Grok (xAI)
- Cannot use structured output (`monadic: true`) with tool execution
- Jupyter Notebook requires post-processing to fix filename issues
- **Model Requirements**: 
  - grok-4-0709 requires minimum 1000 max_tokens (returns empty responses with less)
  - Use grok-4-0709 as default for non-image generation tasks
- **Live Search Parameters**: Full support for all documented parameters
  - Web, X, News, RSS sources with configurable filters
  - Date range filtering with date_from and date_to
  - Country, website filters, and safe search options
- Recommendation: Use for simple tool tasks, not complex workflows

#### Gemini 2.5
- Trade-off: Cannot have both function calling and structured JSON simultaneously
- Use `reasoning_effort: "low"` for function calling apps (better balance)
- Remove `reasoning_effort` for monadic mode apps
- Gemini 2.5 Flash recommended for cost/performance balance
- **Web Search Implementation**: Dual tool approach for comprehensive capabilities
  - `google_search` tool for general web queries (no function_calling_config needed)
  - `url_context` tool automatically activated when URLs detected in messages
  - Provides both search and URL scraping capabilities
- **Google Search Grounding**: Native support with metadata display
  - Shows search queries, grounding chunks, and search entry points
  - Automatically appended to response when web search is enabled

#### Cohere Command-A
- **Reasoning Model**: command-a-reasoning-08-2025 (256K context, 32K output)
  - Supports thinking/reasoning with `reasoning_effort: ["disabled", "enabled"]`
  - Uses `thinking: { type: "enabled" }` API parameter
- **Critical Limitations**:
  - Cannot chain multiple tool calls (single tool execution per request)
  - API returns error 422 "No valid response generated" when thinking enabled with assistant messages
  - Not suitable for Jupyter Notebook or complex workflows
- **Known Issues**:
  - Thinking mode incompatible with conversation history containing assistant messages
  - Single-text workaround attempted but not fully effective
  - Recommendation: Use without thinking for 2nd+ messages or consider alternative providers

## Testing Infrastructure

### Container Networking
- **Selenium Integration**: Docker network correctly resolves selenium_service hostname
  - selenium_service resolves to 172.18.0.4 in Docker network
  - No manual hostname mapping required
  - Test URL changed from example.com to httpbin.org for better reliability

### Voice Pipeline Testing
- **TTS->STT Tests**: Use simple, common phrases for better accuracy
  - Avoid complex punctuation and special characters
  - Accuracy threshold: 30% minimum for reliable testing
  - Clear phrases achieve 100% accuracy

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
HOST_OS=`uname -s`      # Required for Docker Compose (set in Rakefile)
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

*Notes:
- Grok Jupyter has filename display limitations (workaround implemented)
- Claude, Gemini, and Grok Jupyter require `monadic: false` for tool execution
- Only OpenAI Jupyter successfully uses `monadic: true` with tools

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

## Monadic Mode vs Tool Execution

### Key Finding
Providers handle the combination of monadic mode (structured JSON responses) and tool execution differently:

| Provider | Monadic + Tools | Solution | Technical Reason |
|----------|----------------|----------|------------------|
| OpenAI   | ✅ Works       | Can use `monadic: true` | Native `response_format` API support |
| Claude   | ❌ Conflicts   | Must use `monadic: false` | Thinking blocks break JSON structure |
| Gemini   | ❌ Conflicts   | Must use `monadic: false` | API limitation: function calling XOR structured output |
| Grok     | ❌ Conflicts   | Must use `monadic: false` | Implementation limitations |

### Implementation Guidelines
- For tool-heavy apps (Jupyter, Code Interpreter), prefer `monadic: false` for consistency
- Exception: OpenAI can maintain `monadic: true` if JSON structure is beneficial
- Test thoroughly when combining monadic mode with tool execution

## xAI/Grok Specific Limitations

### Sequential Tool Execution Required
- xAI cannot reliably execute multiple tools in a single response
- Complex requests must be broken down into sequential steps
- Jupyter Notebook apps should guide users to make step-by-step requests

### Best Practices for xAI Apps
- Use clear initial greetings explaining sequential operation requirement
- Provide examples of how to break down complex requests
- Set proper user expectations about step-by-step execution

## Current Test Count: 1269 passing tests