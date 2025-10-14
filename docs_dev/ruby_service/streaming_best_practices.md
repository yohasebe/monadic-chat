# Streaming Best Practices

This document captures critical patterns and gotchas discovered while implementing and fixing streaming responses across AI providers.

## Core Streaming Pattern

All vendor helpers should use consistent streaming patterns with `HTTP::Response::Body`:

```ruby
# CORRECT: Use .each for streaming response body
res.each do |chunk|
  chunk = chunk.force_encoding("UTF-8")
  buffer << chunk
  # ... process chunks
end

# INCORRECT: Don't use .each_line (method doesn't exist on HTTP::Response::Body)
res.each_line do |chunk|  # ❌ NoMethodError
  # ...
end

# INCORRECT: Don't convert to string (loses streaming capability)
process_json_data(res: res.body.to_s)  # ❌ Entire response buffered
```

**Key principle**: Pass `res.body` directly to processing functions, not `res.body.to_s`. The `.to_s` conversion forces the entire response to be buffered before processing, defeating the purpose of streaming.

## Provider-Specific Patterns

### Perplexity: Citations in First Chunk

**Critical**: Perplexity sends all citations in the **first response chunk**, not incrementally or in the last chunk.

```ruby
# Store citations from first chunk
stored_citations = nil

res.each do |chunk|
  # ...parse JSON...

  # Capture citations from FIRST chunk only
  if !stored_citations && json["citations"]
    stored_citations = json["citations"]
  end
end

# Use stored_citations for final response, NOT json["citations"] from last chunk
citations = stored_citations  # ✓ Correct
citations = json["citations"]  # ❌ May be nil/empty
```

**Why**: The API design sends metadata upfront. Accessing `json["citations"]` in the last chunk will return nil or empty array.

### Claude: Content Block Events and Web Search

**Critical**: Claude's web search returns multiple content blocks (one per search result/citation). Each `content_block_stop` event should NOT add line breaks.

```ruby
# INCORRECT: Causes excessive line breaks with web search
if json.dig("type") == "content_block_stop"
  res = { "type" => "fragment", "content" => "\n\n" }  # ❌
  block&.call res
end

# CORRECT: Skip content_block_stop events entirely
# Web search returns multiple blocks, each triggering this event
# if json.dig("type") == "content_block_stop"
#   # Skip - causes excessive breaks with web search
# end
```

**Why**: Regular responses have one content block, but web search has many. Adding `\n\n` after each block creates unreadable output during streaming (final result is correct because it's re-rendered from response object).

### DeepSeek: Fragment Filtering During Streaming

**Critical**: Don't block ALL fragments once a pattern is detected. Check patterns **after** streaming completes.

```ruby
# INCORRECT: Blocks all subsequent fragments once pattern matches
if choice["message"]["content"] =~ /tavily_search/
  # This blocks ALL remaining fragments! ❌
elsif fragment.length > 0
  block&.call fragment_res
end

# CORRECT: Only filter special markers during streaming
if fragment.length > 0 && !fragment.match?(/<｜[^｜]+｜>/)
  # Send fragment unless it contains special markers
  block&.call fragment_res  # ✓
end

# Check for function call patterns AFTER streaming completes (lines 125-158)
if content =~ /```json.*"name".*"tavily_search"/m
  # Convert to proper tool call format
end
```

**Why**: The regex checks the **entire accumulated message content**, not just the current fragment. Once it matches, all subsequent fragments are blocked, stopping streaming entirely.

### Gemini: HTTP Response Body Iteration

**Critical**: Use `.each`, not `.each_line` for `HTTP::Response::Body`.

```ruby
# CORRECT
process_json_data(res: res.body)  # Pass body directly

# In process_json_data:
res.each do |chunk|  # ✓ Use .each
  # ...
end

# INCORRECT
res.each_line do |chunk|  # ❌ NoMethodError: undefined method 'each_line'
  # ...
end
```

**Why**: `HTTP::Response::Body` doesn't implement `each_line`. All other providers (DeepSeek, Perplexity, Claude) use `.each` successfully.

## Fragment Sequencing

For proper fragment ordering and debugging, include sequence numbers and timestamps:

```ruby
fragment_sequence = 0

if fragment.length > 0
  res = {
    "type" => "fragment",
    "content" => fragment,
    "sequence" => fragment_sequence,
    "timestamp" => Time.now.to_f
  }
  fragment_sequence += 1
  block&.call res
end
```

This helps identify:
- Out-of-order fragments
- Missing fragments
- Duplicate fragments
- Timing issues

## Testing Streaming Issues

When debugging streaming problems:

1. **Enable EXTRA_LOGGING**: Set `EXTRA_LOGGING=true` in `~/monadic/config/env`
2. **Check chunk reception**: Verify chunks are arriving (log `chunk_count`)
3. **Check fragment sending**: Verify fragments are being sent to UI (log before `block&.call`)
4. **Compare streaming vs final**: Final result is always re-rendered from response object
5. **Look for blocking conditions**: Check for conditions that prevent fragment transmission

Common symptoms:
- **No streaming, but final result correct**: Fragments blocked (DeepSeek pattern)
- **Streaming works, final result wrong**: Data loss during accumulation (Perplexity citations)
- **Excessive line breaks during streaming**: Extra content in fragments (Claude content blocks)
- **NoMethodError on response body**: Wrong iteration method (Gemini each_line)

## Related Documentation

- `docs_dev/ruby_service/thinking_reasoning_display.md` - Reasoning/thinking content handling
- `docs/developer/code_structure.md` - Vendor helper architecture
- `CLAUDE.md` - Provider independence requirements
