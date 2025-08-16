# Development History

*For current technical documentation, see [DEVELOPER_NOTES.md](DEVELOPER_NOTES.md)*

## August 2025 Updates

### Latest Fixes (2025-08-16)
- **Claude Jupyter Notebook**: Confirmed monadic mode incompatibility with tool execution
- **Jupyter Notebook Greeting**: Reverted initial greeting changes that interfered with context formatting
- **Font Configuration**: Corrected Matplotlib to use pre-installed Noto Sans CJK JP fonts

### Previous Fixes (2025-08-14)
- **Claude Batch Processing**: Implemented batch processing for multiple tool calls, improving Jupyter Notebook performance
- **Claude Reasoning Effort**: Set optimal `reasoning_effort: minimal` for all Claude Sonnet 4 apps for better function calling
- **Thinking Budget Fix**: Fixed minimum thinking_budget_tokens requirement (1024) for Claude's minimal reasoning mode

### Earlier Fixes (2025-08-13)
- **GPT-5 Streaming**: Fixed duplicate characters issue by skipping redundant `response.in_progress` events
- **Math Tutor Consolidation**: Created shared constants module reducing 576 lines to 150 lines
- **Markdown Bold Rendering**: Fixed bold text not rendering with Japanese brackets and in numbered lists

### Major Improvements
- **Unified Error Handling System**: Consistent error messages across all providers with user-friendly suggestions
- **MathJax Header Support**: Fixed math rendering in header tags (h1-h6)
- **Grok Jupyter Notebook**: Resolved filename timestamp issues with post-processing workaround

### Provider Enhancements
- **Math Tutor**: Extended support to Claude, Gemini, and Grok (previously OpenAI-only)
- **Jupyter Notebook**: Added support for Gemini and Grok with provider-specific optimizations
- **Voice Pipeline**: Fixed STT test reliability issues

### Key Discoveries
- **Monadic Mode vs Tool Execution**: Claude, Gemini, and Grok require `monadic false` for proper tool execution in Jupyter Notebook
- **OpenAI Exception**: Only OpenAI successfully combines monadic mode (JSON responses) with tool execution
- **Gemini 2.5**: Trade-off between function calling and structured output - cannot have both
- **Grok**: Cannot use monadic mode with tool execution simultaneously  
- **Cohere**: Limited to single tool calls - unsuitable for complex workflows

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
- **Cohere**: Cannot chain multiple tool calls

### System-Wide
- MathJax in headers requires special handling
- Some providers have inconsistent tool response formats
- Monadic mode incompatible with certain tool-heavy workflows

## Claude Monadic Mode Notes

### Current Status
Claude's monadic mode is incompatible with tool-heavy applications due to:
1. **Thinking blocks**: Claude uses `thinking` blocks that interfere with JSON formatting
2. **Markdown habits**: Naturally wraps JSON in code blocks (```json)
3. **Response structure**: Multiple content blocks complicate JSON extraction

### Future Considerations
If attempting to enable monadic mode for Claude in the future:
- Consider disabling `reasoning_effort` (set to "none")
- Implement response post-processing to extract JSON from code blocks
- Add explicit instructions against markdown formatting at multiple points
- Test thoroughly with tool execution scenarios

For detailed technical information, configuration guidelines, and testing procedures, please refer to [DEVELOPER_NOTES.md](DEVELOPER_NOTES.md).