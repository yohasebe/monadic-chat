# Testing Guide

This guide provides a comprehensive overview of Monadic Chat's testing architecture and best practices.

## Visual Test Architecture

```
Monadic Chat Test Architecture (~124 test files = 100 backend + 24 frontend)
├── 📁 spec/ (Backend Ruby tests)
│   ├── 🔧 spec_helper.rb (Minimal setup, no mocks)
│   ├── 📊 examples.txt (Test execution results)
│   ├── 📁 support/
│   │   ├── custom_retry.rb (Retry mechanism)
│   │   └── real_audio_test_helper.rb (TTS/STT helpers)
│   │
│   ├── 📁 unit/ (Fast unit tests - Ruby only)
│   │   ├── 🔬 string_utils_spec.rb
│   │   ├── 🔬 error_pattern_detector_spec.rb
│   │   ├── 🔬 environment_behavior_spec.rb
│   │   ├── 🔬 file_analysis_helper_real_spec.rb
│   │   ├── 🔬 file_naming_conventions_spec.rb
│   │   ├── 🔬 app_loading_real_spec.rb
│   │   ├── 🔬 dsl_tools_block_parsing_spec.rb
│   │   ├── 📁 monadic/
│   │   │   └── 🔬 app_extensions_spec.rb (Core monadic functions)
│   │   └── 📁 utils/
│   │       ├── 🔬 boolean_parser_spec.rb
│   │       ├── 🔬 boolean_parser_with_schema_spec.rb (Schema integration)
│   │       └── 🔬 mdsl_schema_spec.rb (Type management)
│   │
│   ├── 📁 integration/ (Real operations with containers - consolidated)
│   │   ├── 🐳 docker_infrastructure_spec.rb (Container health & Docker commands)
│   │   ├── 🔧 app_helpers_integration_spec.rb (Helper modules & workflows)
│   │   ├── 🗄️ pgvector_integration_real_spec.rb (PostgreSQL + embeddings)
│   │   ├── 🗄️ selenium_integration_spec.rb (Cross-container web scraping)
│   │   ├── 🎤 voice_chat_no_mock_spec.rb (Core voice chat with TTS/STT)
│   │   └── 🎤 voice_pipeline_integration_spec.rb (TTS/STT pipeline testing)
│   │
│   ├── 📁 system/ (App validation)
│   │   ├── ✅ code_interpreter_system_spec.rb
│   │   ├── ✅ chat_system_spec.rb
│   │   ├── ✅ research_assistant_system_spec.rb
│   │   └── [Additional app validation specs...]
│   │
│   └── 📁 e2e/ (End-to-end with real AI APIs)
│       ├── 🔧 e2e_helper.rb (WebSocket & validation helpers)
│       ├── 🔧 validation_helper.rb (Response validation methods)
│       ├── 🤖 chat_openai_spec.rb
│       ├── 🤖 chat_plus_monadic_test_spec.rb
│       ├── 🤖 code_interpreter_spec.rb (Multi-provider)
│       ├── 🤖 content_reader_spec.rb
│       ├── 🤖 image_generator_spec.rb
│       ├── 🤖 jupyter_notebook_spec.rb
│       ├── 🎤 voice_chat_workflow_no_mock_spec.rb
│       ├── 🎤 voice_chat_real_audio_spec.rb
│       ├── 🌐 visual_web_explorer_spec.rb
│       ├── 📊 mermaid_grapher_spec.rb
│       └── 🦙 ollama_spec.rb
│
└── 📁 test/frontend/no-mock/ (Frontend JavaScript tests)
    ├── 📄 README.md (No-mock testing approach documentation)
    ├── 📁 support/
    │   ├── 🔧 no-mock-setup.js (Real DOM environment with jsdom)
    │   ├── 🔧 test-utilities.js (DOM interaction helpers)
    │   └── 🔧 fixture-loader.js (HTML fixture management)
    │
    └── 📁 Tests (24 tests total)
        ├── 🌐 message-input.test.js (7 tests)
        │   ├── ✅ Textarea auto-resize
        │   ├── ✅ Character counter
        │   ├── ✅ IME composition
        │   └── ✅ Paste handling
        ├── 🎨 message-cards.test.js (9 tests)
        │   ├── ✅ Card creation
        │   ├── ✅ Copy/Edit/Delete
        │   └── ✅ Attachments
        └── 🔌 websocket-ui-behavior.test.js (8 tests)
            ├── ✅ Message flow
            ├── ✅ Connection states
            └── ✅ Real-time updates
```

## Test Categories and Dependencies

### Test Execution Matrix

```
📊 Test Categories by Dependencies

┌─────────────────┬─────────────────────────────────┬────────────────┬─────────────────┐
│ Test Type       │ Dependencies                    │ Speed          │ Purpose         │
├─────────────────┼─────────────────────────────────┼────────────────┼─────────────────┤
│ 🔬 Unit         │ Ruby only                       │ ⚡ Very Fast   │ Core logic      │
│ 🗄️ Integration  │ • PostgreSQL + pgvector (Docker)│ 🚀 Fast        │ Real operations │
│                 │ • OpenAI API (for embeddings)   │                │                 │
│                 │ • Python container (Flask API)  │                │                 │
│                 │ • Selenium container            │                │                 │
│ ✅ System       │ Ruby only                       │ 🚀 Fast        │ App validation  │
│ 🐳 Docker       │ • All Docker containers running │ 🐌 Medium      │ Infrastructure  │
│                 │ • Cross-container networking    │                │                 │
│ 🤖 E2E          │ • All Docker containers         │ 🐌 Slow        │ Full workflows  │
│                 │ • AI provider API keys          │                │                 │
│                 │ • WebSocket server              │                │                 │
└─────────────────┴─────────────────────────────────┴────────────────┴─────────────────┘
```

### Docker Container Dependencies

- **PostgreSQL** (port 5433) - pgvector extension for embeddings storage
- **Python** (port 5070) - Flask API for tokenization, Jupyter control
- **Selenium** (port 4444) - Web scraping, screenshot capture
- **Ruby** (port 5001) - Main application server

## Running Tests

### Quick Commands

```bash
# Backend tests (Ruby)
rake                   # Run all backend tests and RuboCop
rake spec              # Run all backend tests
rake spec_unit         # Fast unit tests (~0.1s)
rake spec_integration  # Integration tests with containers
rake spec_system       # System validation tests
rake spec_docker       # Docker infrastructure tests
rake spec_e2e          # End-to-end AI interaction tests

# Frontend tests (JavaScript)
npm run test:no-mock       # Run all UI tests without mocks
npm run test:no-mock:watch # Watch mode for development
```

### E2E Test Subcategories

```bash
# Test specific workflows
rake spec_e2e:chat
rake spec_e2e:code_interpreter
rake spec_e2e:image_generator
rake spec_e2e:pdf_navigator
rake spec_e2e:jupyter_notebook
rake spec_e2e:voice_chat
rake spec_e2e:research_assistant

# Test specific provider
rake spec_e2e:code_interpreter_provider[openai]
rake spec_e2e:code_interpreter_provider[claude]
rake spec_e2e:code_interpreter_provider[gemini]
```

## Test Execution Flow

```
🔄 Automated Test Pipeline

rake spec
├── 1️⃣ Unit Tests (~185 examples, ~0.1s)
│   ├── Core functionality validation
│   ├── No external dependencies
│   └── Immediate feedback
├── 2️⃣ Integration Tests
│   ├── Auto-start containers if needed
│   ├── Real database operations
│   └── Cross-service communication
├── 3️⃣ System Tests
│   ├── MDSL validation
│   ├── App structure checks
│   └── Naming conventions
└── 4️⃣ Docker Tests
    ├── Container health checks
    ├── Network connectivity
    └── Service availability
```

## Testing Philosophy

### Core Principles

1. **No Mocks** - All tests use real implementations
   - Backend: Real containers, databases, and file operations
   - Frontend: Real DOM with jsdom, actual jQuery library
2. **Real Operations** - Actual file I/O, database queries, API calls
3. **Container Auto-Management** - Tests automatically start required containers
4. **Flexible Validation** - Adapt to different AI provider response formats

### Frontend Testing Approach

The frontend tests follow a no-mock philosophy:
- **Real DOM**: Uses jsdom to provide a complete DOM environment
- **Actual Libraries**: Loads the real jQuery library from vendor files
- **Event Simulation**: Tests real browser events and interactions
- **State Verification**: Checks actual DOM state changes
- **No External Dependencies**: Tests run without WebSocket server

### Best Practices

#### Unit Tests
- Should run without any external dependencies
- Focus on single method/class behavior
- Use direct constant manipulation for isolation
- Execution time should be under 0.01s per test

#### Integration Tests
- Test real interactions between components
- Require Docker containers but mock AI API responses
- Verify database operations, file handling, cross-container communication
- Should complete within seconds

#### E2E Tests
- Test complete user workflows with real AI providers
- Accept variations in AI responses
- Use custom retry mechanism for reliability
- May take 30-90 seconds depending on provider

### Writing New Tests

#### Test File Naming
```
spec/unit/feature_name_spec.rb      # Unit tests
spec/integration/feature_name_spec.rb # Integration tests
spec/e2e/feature_workflow_spec.rb   # End-to-end tests
```

#### Test Structure Example
```ruby
RSpec.describe "Feature Name" do
  describe "specific behavior" do
    it "does something specific" do
      # Arrange
      input = prepare_test_data
      
      # Act
      result = perform_action(input)
      
      # Assert
      expect(result).to meet_expectations
    end
  end
end
```

## Continuous Integration

### Automatic Container Management
Integration and E2E tests automatically:
- Check if required containers are running
- Start missing containers
- Wait for containers to be healthy
- Run tests
- Leave containers running for next test run

### Environment Requirements

#### Development Machine
- Ruby 3.0+
- Docker Desktop
- At least one AI provider API key for E2E tests

#### CI Environment
- Set API keys as environment variables
- Ensure Docker is available
- Allow sufficient time for E2E tests (5-10 minutes)

## Troubleshooting

### Common Issues

1. **Container not starting**
   - Check Docker Desktop is running
   - Verify port availability (5433, 5070, 4444, 5001)
   - Check Docker logs: `docker-compose logs [service]`

2. **Integration tests failing**
   - Ensure pgvector extension is installed: `rake spec_docker`
   - Check OpenAI API key is set for embedding tests
   - Verify containers can communicate

3. **E2E tests timing out**
   - Some providers (Claude) have longer response times
   - Increase timeout in test configuration
   - Check API rate limits

### Debug Mode

```bash
# Run with detailed logging
EXTRA_LOGGING=true rake spec

# Run specific test file with focus
rspec spec/unit/specific_test_spec.rb:42
```

## Test Coverage Goals

- **Unit Tests**: 90%+ coverage of core business logic
- **Integration Tests**: All cross-service interactions
- **E2E Tests**: Critical user workflows for each provider
- **Frontend Tests**: All user interaction points
- **Performance**: Unit tests < 1s total, Integration < 30s, E2E < 5min

## Test Coverage Guidelines

When developing tests, focus on:

### Critical Areas
1. **File Operations**
   - Proper input validation
   - Error handling
   - Resource cleanup

2. **External Integrations**
   - API communication
   - Response validation
   - Error recovery

3. **User Input Processing**
   - Input validation
   - Safe data handling
   - Proper escaping

### Integration Points
4. **Third-party Services**
   - Service availability handling
   - Response format validation
   - Timeout management

5. **Audio/Media Processing**
   - Format support
   - Error conditions
   - Performance considerations

## Test Organization Best Practices

### Test Consolidation
The test suite has been consolidated to improve maintainability and reduce duplication:

- **Integration Tests**: Reduced from ~15 files to 6 main files
  - Infrastructure tests separate from application tests
  - Voice chat tests consolidated into core functionality tests
  - Helper modules tested through integration scenarios
  
- **E2E Tests**: Organized by application functionality
  - Multi-provider tests in single files where appropriate
  - Shared validation helpers to reduce duplication
  - Clear separation between workflow types

### Benefits of Consolidation
- ~35% reduction in test files while maintaining full coverage
- Faster test execution due to reduced duplication
- Clearer test boundaries and responsibilities
- Easier maintenance with fewer files to update

### Key Principles
- **No Mocks**: All tests use real implementations
- **Clear Separation**: Infrastructure vs application logic
- **Flexible Validation**: Accept provider response variations
- **Real Dependencies**: Use actual containers and services

### Current Test Structure
- **E2E Tests**: Mix of old `_workflow_spec.rb` pattern (11 files) and new consolidated pattern (5 files)
- **Helper Methods**: All E2E tests must use `with_e2e_retry(max_attempts: 3, wait: 10)` syntax
- **Total Test Count**: ~64 test files across all categories
- **Partial Consolidation**: Voice Chat and Code Interpreter tests consolidated; others remain in original format

## Related Documentation

- [Rake Tasks Guide](rake_tasks.md) - All available rake commands
- [Development Workflow](development_workflow.md) - Development best practices
- [Code Structure](code_structure.md) - Project organization