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

## Realtime TTS with EventMachine

**Critical**: When implementing realtime TTS during streaming, use EventMachine-compatible async HTTP instead of blocking HTTP calls.

### Sentence Segmentation Strategy

**Optimal threshold**: `segments.size >= 1` (send as soon as first complete sentence is ready)

```ruby
# BEFORE: Wait for 2 sentences (slow)
if !cutoff && segments.size >= 2
  complete_sentences = segments[0...-1]
end

# AFTER: Send as soon as 1 sentence complete (fast)
if !cutoff && segments.size >= 1
  complete_sentences = segments[0...-1]
end
```

**Why this works:**
- First sentence typically completes within 500ms (faster perceived response)
- PragmaticSegmenter handles 60+ languages automatically (no manual punctuation rules needed)
- Maintains natural intonation by preserving complete sentences
- `segments[0...-1]` ensures last incomplete sentence stays in buffer

**Language independence:**
- Japanese: "こんにちは。" (。で判定)
- English: "Hello." (.で判定)
- Chinese: "你好。" (。で判定)
- No manual punctuation configuration required

### Architecture: Async HTTP with Sequence Ordering

```ruby
# INCORRECT: Blocking HTTP in EventMachine environment
def streaming_loop
  http.get.each do |chunk|
    tts_result = HTTP.post(tts_url, body: text)  # ❌ Blocks EventMachine reactor
    send_audio(tts_result)
  end
end

# INCORRECT: Worker Thread + Queue pattern
def streaming_loop
  @tts_queue = Queue.new
  @worker_thread = Thread.new do
    loop { tts_result = HTTP.post(tts_url, body: @tts_queue.pop) }  # ❌ Still blocks
  end
end

# CORRECT: EventMachine async HTTP with sequence ordering
require 'em-http-request'

def streaming_loop
  @realtime_tts_sequence_counter ||= 0

  http.get.each do |chunk|
    complete_sentences.each do |sentence|
      @realtime_tts_sequence_counter += 1
      sequence_num = @realtime_tts_sequence_counter
      sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

      # Non-blocking async request
      tts_api_request_em(
        sentence,
        provider: provider,
        sequence_id: sequence_id
      ) do |res_hash|
        @channel.push(res_hash.to_json)  # Callback fires when complete
      end
    end
  end

  # CRITICAL: Process final incomplete sentence after streaming ends
  final_text = buffer.join
  if final_text.strip != ""
    @realtime_tts_sequence_counter += 1
    sequence_num = @realtime_tts_sequence_counter
    sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"  # Same format!

    tts_api_request_em(final_text, sequence_id: sequence_id) do |res_hash|
      @channel.push(res_hash.to_json)
    end
  end
end
```

**Why this pattern works:**
1. **EventMachine::HttpRequest**: Non-blocking, uses callbacks instead of blocking
2. **Sequence numbering**: Handles out-of-order HTTP responses (network latency varies)
3. **Consistent format**: Final segment uses same `"seq#{num}_..."` format as streaming segments
4. **Client-side reordering**: Segments arrive out-of-order but play in sequence order

### Client-Side Reordering Buffer

Since async HTTP requests complete in random order based on network latency, implement a client-side pending buffer:

```javascript
// Track expected sequence and pending out-of-order segments
let nextExpectedSequence = 1;
let pendingAudioSegments = {};

function parseSequenceNumber(sequenceId) {
  const match = sequenceId.match(/^seq(\d+)_/);  // Extract number from "seq5_timestamp_hex"
  return match ? parseInt(match[1], 10) : null;
}

function addToAudioQueue(audioData, sequenceId, mimeType) {
  const sequenceNum = parseSequenceNumber(sequenceId);

  if (sequenceNum !== null) {
    // Store in pending buffer
    pendingAudioSegments[sequenceNum] = {
      data: audioData,
      sequenceNum: sequenceNum,
      timestamp: Date.now()
    };
    processSequentialAudio();
  } else {
    // No sequence number → regular queue (immediate playback)
    globalAudioQueue.push({ data: audioData });
    processGlobalAudioQueue();
  }
}

function processSequentialAudio() {
  // Check if we have the next expected segment
  if (pendingAudioSegments[nextExpectedSequence]) {
    const segment = pendingAudioSegments[nextExpectedSequence];
    delete pendingAudioSegments[nextExpectedSequence];

    // CRITICAL: Clear timeout when expected segment arrives
    if (sequenceCheckTimer) {
      clearTimeout(sequenceCheckTimer);
      sequenceCheckTimer = null;
    }

    globalAudioQueue.push(segment);
    nextExpectedSequence++;

    if (!isProcessingAudioQueue) {
      processGlobalAudioQueue();
    }

    // Recursively process next segment
    setTimeout(() => processSequentialAudio(), 0);
  } else {
    // Missing segment - set up timeout to skip it (only if not already set)
    if (!sequenceCheckTimer && Object.keys(pendingAudioSegments).length > 0) {
      sequenceCheckTimer = setTimeout(() => {
        // Skip to next available segment if current segment never arrives
        const available = Object.keys(pendingAudioSegments).map(k => parseInt(k)).sort();
        if (available.length > 0) {
          nextExpectedSequence = available[0];
          sequenceCheckTimer = null;
          processSequentialAudio();
        }
      }, 5000);
    }
  }
}

// CRITICAL: Reset sequence tracking on new message
function clearAudioQueue() {
  nextExpectedSequence = 1;
  pendingAudioSegments = {};
  if (sequenceCheckTimer) clearTimeout(sequenceCheckTimer);
}
```

### Common Pitfalls

**1. Ruby Closure Variable Capture Bug**
```ruby
# WRONG: Loop variable captured by reference, causes all procs to use last value
complete_sentences.each do |sentence|
  text = sentence  # text is reassigned in each iteration

  EventMachine.defer(
    proc {
      tts_api_request(text, ...)  # ❌ Captures 'text' by reference!
    },
    proc { |res_hash| ... }
  )
end

# Scenario:
# 1. Loop iteration 1: text = "こんにちは！", EventMachine.defer created
# 2. Loop iteration 2: text = "お疲れ様です。", EventMachine.defer created
# 3. Both procs execute: Both see text = "お疲れ様です。" (last value!)
# Result: First sentence skipped, second sentence played twice

# CORRECT: Explicitly capture value before closure creation
complete_sentences.each do |sentence|
  text = sentence

  # Create local variables to capture current values
  sentence_text = text  # ✓ Value captured, not reference
  sequence_id = "seq#{n}_..."

  EventMachine.defer(
    proc {
      tts_api_request(sentence_text, ...)  # ✓ Uses captured value
    },
    proc { |res_hash|
      res_hash["sequence_id"] = sequence_id  # ✓ Uses captured value
      @channel.push(res_hash.to_json)
    }
  )
end
```

**Why this happens:**
- Ruby closures capture variables **by reference**, not by value
- Loop variables are reassigned each iteration, but proc still holds the reference
- By the time EventMachine.defer executes the proc, the variable has been reassigned
- Solution: Create a local variable to explicitly capture the current value

**2. Timer Leak in Sequence Processing**
```javascript
// WRONG: Timer not cleared when expected segment arrives
function processSequentialAudio() {
  if (pendingAudioSegments[nextExpectedSequence]) {
    // Process segment but don't clear timer ❌
    globalAudioQueue.push(segment);
    nextExpectedSequence++;
  } else {
    sequenceCheckTimer = setTimeout(() => { ... }, 5000);
  }
}

// Scenario:
// 1. seq17 arrives first → timer starts (5 seconds)
// 2. seq16 arrives 3 seconds later → processed successfully
// 3. Timer still running! → May fire and corrupt nextExpectedSequence
// 4. seq16 skipped or played out of order

// CORRECT: Clear timer when expected segment arrives
function processSequentialAudio() {
  if (pendingAudioSegments[nextExpectedSequence]) {
    // Clear timer immediately ✓
    if (sequenceCheckTimer) {
      clearTimeout(sequenceCheckTimer);
      sequenceCheckTimer = null;
    }
    globalAudioQueue.push(segment);
    nextExpectedSequence++;
  } else {
    if (!sequenceCheckTimer) {
      sequenceCheckTimer = setTimeout(() => { ... }, 5000);
    }
  }
}
```

**3. Counter Initialized Inside Streaming Loop**
```ruby
# WRONG: Counter initialized inside streaming loop (resets on every fragment)
def streaming_loop
  buffer = []

  responses = app_obj.api_request("user", session) do |fragment|
    # This block executes multiple times during streaming
    text = fragment["content"]
    buffer << text
    segments = PragmaticSegmenter::Segmenter.new(text: buffer.join).segment

    if segments.size >= 2
      if auto_tts_realtime_mode
        # ❌ Counter initialized INSIDE the streaming loop!
        @realtime_tts_sequence_counter = 0

        segments[0...-1].each do |sentence|
          @realtime_tts_sequence_counter += 1
          sequence_id = "seq#{@realtime_tts_sequence_counter}_..."  # Always seq1!
          tts_api_request_em(sentence, sequence_id: sequence_id)
        end
      end
    end
  end
end

# Scenario:
# 1. First fragment: "こんにちは！" → counter = 0, increments to 1 → seq1 ✓
# 2. Second fragment: "お疲れ様です。" → counter = 0 (reset!), increments to 1 → seq1 ❌
# 3. Third fragment: "今日は..." → counter = 0 (reset!), increments to 1 → seq1 ❌
# Result: All sentences get seq1, client waits 5 seconds for seq2 that never comes

# CORRECT: Counter initialized OUTSIDE streaming loop (once per message)
def streaming_loop
  buffer = []

  # ✓ Initialize counter ONCE at Thread start, before streaming begins
  @realtime_tts_sequence_counter = 0

  responses = app_obj.api_request("user", session) do |fragment|
    # This block executes multiple times, but counter persists
    text = fragment["content"]
    buffer << text
    segments = PragmaticSegmenter::Segmenter.new(text: buffer.join).segment

    if segments.size >= 2
      if auto_tts_realtime_mode
        segments[0...-1].each do |sentence|
          @realtime_tts_sequence_counter += 1  # Increments correctly: 1, 2, 3...
          sequence_id = "seq#{@realtime_tts_sequence_counter}_..."
          tts_api_request_em(sentence, sequence_id: sequence_id)
        end
      end
    end
  end

  # Final segment also increments counter correctly
  @realtime_tts_sequence_counter += 1
  sequence_id = "seq#{@realtime_tts_sequence_counter}_..."
end
```

**Why this happens:**
- The `app_obj.api_request do |fragment|` block executes **multiple times** during streaming
- Variables initialized inside this block get reset on every fragment
- Instance variables (`@var`) persist within Thread scope but are re-assigned if inside the loop
- Solution: Initialize counter **before** the streaming loop, at Thread start

**Symptoms:**
- First TTS response smooth, but 2nd+ responses delayed ~5 seconds before speech starts
- Strange audio glitches (e.g., "せえぜろぜろ" before "それぞれ")
- Logs show multiple sentences with same sequence number (all seq1)
- Client-side pending buffer grows indefinitely waiting for seq2, seq3...

**4. Inconsistent Sequence ID Format**
```ruby
# WRONG: Final segment uses different format
streaming_segment_id = "seq1_#{Time.now.to_f}_#{SecureRandom.hex(2)}"  # ✓ "seq1_..."
final_segment_id = "#{Time.now.to_f}_final"  # ❌ "timestamp_final"

# Client-side parseSequenceNumber() returns null for final segment
# → Goes to regular queue instead of sequential buffer
# → Plays immediately, before earlier segments

# CORRECT: All segments use same format
final_segment_id = "seq5_#{Time.now.to_f}_#{SecureRandom.hex(2)}"  # ✓ "seq5_..."
```

**5. Missing Final Sentence**
```ruby
# WRONG: Only process complete sentences during streaming
complete_sentences.each { |s| send_tts(s) }
# Final incomplete sentence remains in buffer → never sent

# CORRECT: Process remaining buffer after streaming ends
after_streaming do
  final_text = buffer.join
  send_tts(final_text) if final_text.strip != ""
end
```

**6. Forgetting to Reset Sequence on New Message**
```javascript
// WRONG: Sequence counter continues from previous message
// User sends message 1 (seq1, seq2, seq3)
// User sends message 2 (seq4, seq5, seq6)  ❌ Should restart at seq1

// CORRECT: Reset counter when sending new message
sendButton.addEventListener('click', () => {
  clearAudioQueue();  // Resets nextExpectedSequence = 1
  sendMessage();
});
```

### Testing Realtime TTS Issues

When debugging realtime TTS problems:

1. **Check sequence ID format**: All segments should match `^seq\d+_` pattern
2. **Enable EXTRA_LOGGING**: Verify async callbacks are firing
3. **Check log timestamps**: Callbacks may complete out-of-order (seq1, seq3, seq2)
4. **Verify client-side buffering**: `pendingAudioSegments` should reorder correctly
5. **Test timeout behavior**: Skip to next segment after 5 seconds if current segment stuck

Common symptoms:
- **Last sentence missing**: Final segment not processed after streaming ends
- **Scrambled audio order**: Async responses not reordered client-side
- **Final segment plays first**: Format mismatch sends final segment to regular queue
- **Random segments skipped**: Timer leak causes timeout to fire after segment arrives
- **Audio stuck/frozen**: Sequence counter not reset between messages
- **First sentence skipped, second played twice**: Ruby closure variable capture bug (loop variable reassigned before proc executes)
- **2nd+ messages delayed ~5 seconds, strange audio glitches**: Counter initialized inside streaming loop (resets on every fragment)

### Configuration

Enable realtime TTS mode in `~/monadic/config/env`:

```bash
AUTO_TTS_REALTIME_MODE=true  # TTS during streaming (not after completion)
EXTRA_LOGGING=true           # Debug async callback order
```

### UI Enhancement: Stop Button Highlighting

**Feature**: Visual feedback for TTS playback status by highlighting the Stop button with a pulsing animation.

**Challenge**: Auto TTS timing mismatch - audio segments arrive **after** assistant card creation.

```
Timeline:
1. Streaming starts → temp-card shows text
2. HTML message arrives → final card created (audio queue empty)
3. Audio segments arrive → seq1 detected → highlight Stop button
4. Audio plays → Stop button pulses
5. Playback ends or Stop clicked → highlight clears
```

**Implementation Pattern:**

```javascript
// WRONG: Highlight when card created (queue is empty at this point)
function handleHtmlMessage(data) {
  createCard(data.content);
  if (globalAudioQueue.length > 0) {  // ❌ Always false for Auto TTS
    highlightStopButton(data.content.mid);
  }
}

// CORRECT: Highlight when first audio segment arrives
function processSequentialAudio() {
  if (pendingAudioSegments[nextExpectedSequence]) {
    const isFirstSegment = nextExpectedSequence === 1;

    if (isFirstSegment && globalAudioQueue.length === 0) {
      // Find latest assistant card (excluding temp-card)
      const $cards = $('.role-assistant').closest('.card').not('#temp-card');
      const cardId = $cards.last().attr('id');
      highlightStopButton(cardId);  // ✓ Card exists, audio about to play
    }

    globalAudioQueue.push(segment);
    nextExpectedSequence++;
  }
}

// Stop button removal on completion
function processGlobalAudioQueue() {
  if (globalAudioQueue.length === 0) {
    removeStopButtonHighlight();  // ✓ Auto-clear when queue empty
    return;
  }
  // Process next segment...
}
```

**Key Points:**
1. **Timing**: Highlight on **first audio segment arrival**, not card creation
2. **Filtering**: Exclude `#temp-card` (hidden but still in DOM after `.hide()`)
3. **Array Reference**: Use `.length = 0` instead of `= []` to preserve window reference
4. **Getter Function**: Export boolean state via getter (`getIsProcessingAudioQueue()`) not direct value
5. **Automatic Cleanup**: Remove highlight when queue empties or Stop clicked

**CSS Animation:**

```css
.func-stop.tts-active i {
  color: #DC4C64 !important;
  animation: tts-pulse 1.5s ease-in-out infinite;
}

@keyframes tts-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.7; transform: scale(1.1); }
}
```

**Buffer Configuration:**

Unified buffer threshold for consistent TTS behavior:

```ruby
# websocket.rb
REALTIME_TTS_MIN_LENGTH = 60  # Characters

# Behavior:
# - Sentences ≤ 60 chars: buffered
# - Buffer flushed when total > 60 chars
# - Reduces API calls while maintaining responsiveness
```

**Benefits:**
- User awareness of active TTS playback
- Clear indication Stop button is clickable
- Consistent behavior across Play button and Auto TTS modes
- Automatic cleanup without manual intervention

## Related Documentation

- `docs_dev/ruby_service/thinking_reasoning_display.md` - Reasoning/thinking content handling
- `docs_dev/developer/code_structure.md` - Vendor helper architecture
- `CLAUDE.md` - Provider independence requirements
