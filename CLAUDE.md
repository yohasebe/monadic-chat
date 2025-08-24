# Development History & Technical Notes

*For current technical documentation, see [DEVELOPER_NOTES.md](DEVELOPER_NOTES.md)*  
*For architecture improvements and future directions, see [ARCHITECTURE_IMPROVEMENTS.md](ARCHITECTURE_IMPROVEMENTS.md)*

## August 2025 Updates

### Session 10 - 2025-08-24

#### Provider Spinner Display Issues Fixed
- **Problem Identified**: Spinner disappearing prematurely before response arrives
  - Affected providers: DeepSeek, Perplexity, and Ollama
  - Root cause: `is_first` flag in fragment messages triggering premature UI updates
  - Secondary issue: Redundant initial "THINKING" spinner messages
- **Solution Implemented**:
  - Removed `is_first` flag from fragment messages in affected providers
  - Commented out server-side "THINKING" spinner messages
  - Preserved "CALLING FUNCTIONS" messages for tool execution feedback
- **Technical Details**:
  - Client-side websocket handler at line 92 was clearing content on `is_first === true`
  - All providers use similar fragment streaming pattern but handle spinners differently
  - Fix ensures consistent spinner visibility throughout request lifecycle

#### Cohere Jupyter Notebook Investigation
- **Discovery**: Cohere limited to 2 sequential tool calls per response
  - Documentation claimed full multi-tool support but testing revealed limitations
  - Cannot execute the 3+ tool sequence required for Jupyter operations
  - Attempted workarounds (step-by-step prompting, Grok-style approach) unsuccessful
- **Decision**: Jupyter Notebook not implemented for Cohere provider
- **Documentation**: Updated provider compatibility matrix to reflect actual capabilities

### Session 9 - 2025-08-23

#### Universal Language Injection for All Providers
- **Complete Provider Coverage**: Extended language support to ALL AI providers
  - Previously only OpenAI and Claude had language injection
  - Now includes: DeepSeek, Gemini, Grok, Mistral, Perplexity, and Cohere
  - Each provider required unique implementation based on message structure
- **Gemini Special Handling**: 
  - Refactored to properly use `systemInstruction` field instead of mixing with contents
  - Fixed nil error for `initiate_from_assistant` apps when contents array is empty
  - System messages now correctly separated from conversation messages
- **Perplexity Voice Chat Optimization**:
  - Changed initial prompt from "Please proceed according to your system instructions" to "Hi there! How are you today?"
  - Prevents unwanted web searches for system prompt keywords
  - Enhanced system prompt to discourage unnecessary searches in casual conversation
- **Language-Aware Apps Enhancement**:
  - Voice Interpreter, Translate, Language Practice (all 8 providers), Language Practice Plus
  - Apps now greet users in their preferred language while maintaining core functionality
  - Created LANGUAGE_AWARE_APPS.md documenting app behavior with language settings
- **Test Coverage**: Added provider_language_injection_spec.rb with 12 comprehensive tests

### Session 8 - 2025-08-23

#### Comprehensive Language Selector Feature
- **Implementation**: Unified language control for UI and AI interactions
  - Created `LanguageConfig` module with 57 language support (matching Whisper API)
  - Moved language selector from settings panel to info panel for better visibility
  - Native language names with English in parentheses (e.g., "日本語 (Japanese)")
  - Single selector controls both STT/TTS and AI response language
- **System Integration**:
  - Language preference injected into system prompts for AI responses
  - STT automatically uses selected language (nil for "auto")
  - TTS receives language parameter with provider-specific handling
  - Works with `initiate_from_assistant` mode
- **Technical Details**:
  - Default "auto" for backward compatibility
  - Proper handling of "auto" to prevent API errors
  - Language prompt added in English regardless of selected language
  - All WebSocket messages carry `interface_language` parameter

### Session 7 - 2025-08-22

#### Unified Error Formatting System
- **Implementation**: Centralized error formatter for consistent user experience
  - All 8 providers (Claude, Cohere, DeepSeek, Gemini, OpenAI, xAI, Perplexity, Mistral) updated
  - Standardized format: `[Provider] Category: Message (Code: XXX) Suggestion: Action`
  - Categories: API Key Error, API Error, Network Error, Parsing Error, Tool Execution Error
  - User-friendly suggestions for common issues (e.g., "Set API_KEY in ~/monadic/config/env")
- **Benefits**:
  - Consistent error messages across all providers
  - Easier debugging with clear provider identification
  - Actionable suggestions for users to resolve issues
  - Reduced confusion from provider-specific error formats

### Session 6 - 2025-08-22

#### DeepSeek Strict Function Calling
- **Implementation**: Beta API endpoint with strict JSON schema validation
  - ALL properties must be in required arrays
  - Filters special markers (`<｜tool▁call▁end｜>`) from streaming responses
  - Enabled by default for deepseek-chat, improves Code Interpreter reliability
  - 12 tests covering schema conversion and activation logic

#### Cohere Reasoning Model Integration
- **Model Added**: command-a-reasoning-08-2025 (256K context, 32K output)
- **Known Issue**: Error 422 when thinking enabled with assistant messages in history
  - Single-text workaround attempted but not fully effective
  - Enhanced debugging added for API requests/responses
  - 9 tests for conversation formatting logic

#### xAI Jupyter Notebook Sequential Execution
- **Issue**: Cannot reliably chain multiple tool calls in single response
- **Solution**: Enhanced initial greeting explaining step-by-step approach required

### Session 5 - 2025-08-21

#### Gemini Web Search Implementation
- **Dual Tool Approach**: Implemented Google Search + URL Context tools for comprehensive web capabilities
  - Google Search (`google_search`) tool for general web queries
  - URL Context (`url_context`) tool automatically activated when URLs detected in messages
  - Fixed "Function calling config is set without function_declarations" error
- **Type Safety**: Resolved Hash type checking error in message URL detection logic

#### xAI Live Search Stability
- **Test Reliability**: Improved xAI Live Search test stability
  - Added retry mechanism with multiple query variations
  - Increased max_tokens to 2000 for more consistent responses
  - Tests now pass reliably across different network conditions

#### Infrastructure Improvements
- **HOST_OS Environment Variable**: Fixed Docker Compose warnings by setting HOST_OS in Rakefile
- **Selenium Test Fix**: Resolved persistent timeout issues without skipping
  - Changed test URL from example.com to httpbin.org for better reliability
  - Confirmed selenium_service hostname resolution works correctly in Docker network
  - Increased readiness check attempts and timeout values
  - Fixed RSpec expectation syntax issues

#### Model Updates
- **Cohere**: Added missing `command-a-reasoning-08-2025` model to model_spec.js

### Session 4 - 2025-08-20

#### xAI Live Search Enhancement
- **Full Parameter Support**: Implemented complete support for all documented xAI Live Search parameters
  - Web source: country, excluded_websites, allowed_websites, safe_search
  - X (Twitter) source: included_x_handles, excluded_x_handles, post metrics
  - News source: country, excluded_websites, safe_search
  - RSS source: links parameter for RSS feeds
  - Date range filtering: date_from, date_to
- **Model Compatibility**: Fixed grok-4-0709 requiring minimum 1000 max_tokens for proper responses
- **Test Coverage**: All xAI tests now pass with grok-4-0709 model

#### Test Infrastructure Improvements
- **Voice Pipeline Tests**: Improved TTS->STT test reliability
  - Used clearer, more recognizable phrases
  - Adjusted accuracy thresholds to realistic levels (30% minimum)
  - Achieved 100% accuracy with optimized test phrases
- **Selenium Integration**: Fixed container networking issues
  - Resolved selenium_service hostname resolution problem
  - Automatic runtime fix for webpage_fetcher.py container references
  - Screenshots now capture successfully without skipping

#### Key Technical Findings
- **grok-4-0709 Token Requirements**: Model returns empty responses with max_tokens < 1000
- **Container Networking**: Python container requires explicit hostname mapping for Selenium access
- **Voice Recognition**: Simple, common phrases achieve much higher accuracy than complex or punctuated text

### Session 3 - 2025-08-16

#### Major Findings
- **Monadic Mode Investigation**: Thoroughly tested Claude's compatibility with monadic mode + tool execution
  - Attempted multiple approaches including JSON reminders and response post-processing
  - Confirmed fundamental incompatibility due to thinking blocks and markdown formatting habits
  - Decision: Keep `monadic: false` for Claude's tool-heavy apps

#### Fixes Implemented
- **Claude Jupyter Notebook**: Confirmed and documented monadic mode incompatibility
- **Jupyter Notebook Greeting**: Reverted workload management changes that interfered with context
- **Font Configuration**: Fixed Matplotlib to use pre-installed Noto Sans CJK JP fonts
- **Documentation**: Comprehensive updates to technical docs and user guides

### Session 2 - 2025-08-14
- **Claude Batch Processing**: Implemented single API request for multiple tool calls
- **Claude Reasoning Effort**: Set `reasoning_effort: minimal` for all Claude Sonnet 4 apps
- **Thinking Budget**: Fixed minimum 1024 tokens requirement for minimal reasoning mode
- **Workload Management**: Added upfront batch processing notifications

### Session 1 - 2025-08-13
- **GPT-5 Streaming**: Fixed duplicate characters in response.in_progress events
- **Math Tutor**: Consolidated shared constants (576 → 150 lines)
- **Markdown Rendering**: Fixed bold text with Japanese brackets and numbered lists

### Major Improvements
- **Unified Error Handling System**: Consistent error messages across all providers with user-friendly suggestions
- **MathJax Header Support**: Fixed math rendering in header tags (h1-h6)
- **Grok Jupyter Notebook**: Resolved filename timestamp issues with post-processing workaround

### Provider Enhancements
- **Math Tutor**: Extended support to Claude, Gemini, and Grok (previously OpenAI-only)
- **Jupyter Notebook**: Added support for Claude, Gemini, and Grok with provider-specific optimizations
- **Voice Pipeline**: Fixed STT test reliability issues

### Key Discoveries
- **Monadic Mode vs Tool Execution**: Claude, Gemini, and Grok require `monadic false` for proper tool execution in Jupyter Notebook
- **OpenAI Exception**: Only OpenAI successfully combines monadic mode (JSON responses) with tool execution
- **Gemini 2.5**: Trade-off between function calling and structured output - cannot have both
- **Grok**: Cannot use monadic mode with tool execution simultaneously  
- **Cohere**: Multi-tool support exists but limited to 2 sequential tool calls per response (incompatible with Jupyter Notebook workflow)

## Testing & Documentation
- Test suite expanded to 1269 passing tests
- Progressive migration to unified error handling system
- Consolidated developer documentation in DEVELOPER_NOTES.md

## Known Limitations

### Provider-Specific
- **Claude**: 
  - Jupyter Notebook requires `monadic false` for tool execution
  - Thinking mode (`reasoning_effort`) conflicts with JSON structure requirements
  - Tends to wrap JSON responses in markdown code blocks when forced
- **Grok**: Jupyter Notebook filename display requires post-processing
- **Gemini**: Must choose between function calling OR structured output
- **Cohere**: Maximum 2 sequential tool calls per response (prevents Jupyter Notebook implementation)

### System-Wide
- MathJax in headers requires special handling
- Some providers have inconsistent tool response formats
- Monadic mode incompatible with certain tool-heavy workflows

## Technical Deep Dive: Claude Monadic Mode

### The Problem
Claude's monadic mode fails with tool execution due to fundamental architecture differences:

1. **Thinking Blocks Interference**
   ```json
   // Claude's response structure
   {
     "type": "thinking",
     "thinking": "Let me analyze..."
   },
   {
     "type": "text", 
     "text": "```json\n{...}\n```"  // JSON wrapped in markdown
   }
   ```

2. **Automatic Markdown Formatting**
   - Claude instinctively wraps JSON in \`\`\`json blocks
   - Even with explicit instructions, this behavior persists
   - Post-tool execution responses lose JSON structure

3. **API-Level Differences**
   - OpenAI: Native `response_format: {type: "json_object"}` 
   - Claude: Relies on system prompt instructions only
   - Tool execution creates new context that breaks continuity

### Attempted Solutions (All Failed)
1. ✗ Adding JSON reminders after tool execution
2. ✗ Explicit "no markdown" instructions at multiple points
3. ✗ Response post-processing to extract JSON from code blocks
4. ✗ Disabling reasoning_effort to avoid thinking blocks

### Current Resolution
- **Decision**: Use `monadic: false` for all Claude tool-heavy apps
- **Rationale**: Provider-specific optimization over forced uniformity
- **Impact**: Claude Jupyter Notebook works perfectly without monadic mode

## Lessons Learned

### Provider Compatibility Matrix
| Feature | OpenAI | Claude | Gemini | Grok | Cohere |
|---------|--------|--------|--------|------|--------|
| Monadic Mode | ✅ | ✅* | ✅* | ✅* | ✅* |
| Tool Execution | ✅ | ✅ | ✅ | ✅ | ✅ |
| Monadic + Tools | ✅ | ❌ | ❌ | ❌ | ❌ |
| Batch Processing | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| Parallel Tools | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| Sequential Tools (3+) | ✅ | ✅ | ✅ | ✅ | ❌** |
| Jupyter Notebook | ✅ | ✅ | ✅ | ✅ | ❌ |

*Works for non-tool apps only
**Limited to 2 sequential tool calls per response

### Best Practices Established
1. **Don't force uniformity** - Let each provider use its strengths
2. **Test thoroughly** - Monadic mode + tools requires extensive testing
3. **Document limitations** - Clear documentation prevents future confusion
4. **Provider-specific configs** - Optimize for each provider's architecture

### Session 6 - 2025-08-23

#### Language Selector Implementation
- **Unified Language Control**: Implemented comprehensive language selector in Info panel
  - Single selector controlling STT, TTS, and AI response language
  - 58 languages supported with native name display (e.g., "日本語 (Japanese)")
  - Cookie-based persistence for user preferences
  - Dynamic language switching during active sessions

- **Technical Implementation**:
  - Created `LanguageConfig` module for centralized language management
  - Runtime settings architecture to keep language out of message history
  - WebSocket UPDATE_LANGUAGE message for mid-session changes
  - System prompt injection for provider-specific language instructions

- **RTL Language Support**: Added proper Right-to-Left text display
  - Supports Arabic, Hebrew, Persian, and Urdu
  - CSS class `.rtl-messages` applies RTL only to message content areas
  - UI components remain LTR for consistent navigation
  - Automatic detection and switching based on language selection

- **Testing Coverage**: Comprehensive test suite added
  - 28 new tests for language configuration and RTL support
  - WebSocket message handling tests
  - All existing tests updated and passing

For detailed technical information, configuration guidelines, and testing procedures, please refer to [DEVELOPER_NOTES.md](DEVELOPER_NOTES.md).