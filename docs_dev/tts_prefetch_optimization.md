# TTS Prefetch Optimization

## Overview

Text-to-Speech (TTS) performance has been optimized using a prefetch pipeline that generates audio for upcoming text segments while the current segment is playing. This significantly reduces waiting time and improves user experience.

## Implementation Details

**Location:** `docker/services/ruby/lib/monadic/utils/websocket.rb` (PLAY_TTS handler, lines ~1452-1670)

### How Prefetch Works

1. **Text Segmentation**: Text is split into sentences using `PragmaticSegmenter`
2. **Parallel Processing**: Up to 2 TTS API requests run concurrently
3. **Pipeline Execution**:
   - Start API requests for segments 0 and 1
   - While segment 0 plays, segment 1 is being generated
   - When segment 1 starts playing, segment 2 begins generating
   - Continue until all segments are processed

### Benefits

- **Faster Playback Start**: First segment plays as soon as it's ready
- **Seamless Transitions**: Next segment is ready by the time current segment finishes
- **Optimized Resource Usage**: Only 2 concurrent requests to avoid rate limits

## Provider-Specific Behavior

### ElevenLabs (Flash, Multilingual, V3)

- **Segmentation**: Split by sentences
- **Prefetch**: Enabled (2 concurrent requests)
- **Context Continuity**: Supported via API parameters
  - `previous_text`: ✅ Implemented in Monadic Chat (`interaction_utils.rb:371-373`)
  - `next_text`: ❌ Not implemented (API supports this feature)
  - Provides better voice continuity across segments

### OpenAI TTS (Standard, HD, 4o Mini)

- **Segmentation**: Split by sentences
- **Prefetch**: Enabled (2 concurrent requests)
- **Context Continuity**: ❌ Not available (API does not support context parameters)

### Gemini TTS (Flash, Pro)

- **Segmentation**: Split by sentences (with minimum length validation)
- **Prefetch**: Enabled (2 concurrent requests)
- **Context Continuity**: ❌ Not available via parameters
  - Uses session-level context (32k token window) instead
  - Style prompts provide tone/delivery control

### ElevenLabs V3 Specific Behavior

**Default Behavior (Prefetch Enabled):**
- Segments are split for prefetch benefits
- Faster playback start
- Configuration: No setting needed (default)

**Legacy Behavior (Optional):**
- All text combined into single segment
- Slower playback start (waits for entire text)
- Configuration: Set `ELEVENLABS_V3_COMBINE_SEGMENTS=true` in `~/monadic/config/env`

**Why V3 Was Different Initially:**
ElevenLabs V3 was originally designed to process all text at once for optimal quality. However, this meant no prefetch benefits. The new default behavior enables prefetch while maintaining quality.

### Web Speech API

- **Processing**: Client-side (browser native)
- **Prefetch**: Not applicable (no API calls)
- **Performance**: Instant (no network delay)

### Gemini TTS

- **Special Processing**: Short segments are combined to avoid API failures
- **Minimum Length**: 8 characters (cleaned text)
- **Prefetch**: Enabled for combined segments

## Code Simplification and Quality Improvements (2024-10-14)

### Gemini TTS Endpoint Optimization

**Problem:** Gemini TTS used `streamGenerateContent` endpoint with complex streaming logic (80+ lines), but API returns complete audio in one response anyway.

**Solution:**
- Changed to `generateContent` endpoint for all requests
- Removed unnecessary streaming-specific code (80 lines)
- Unified with standard non-streaming response handling

**Results:**
- No latency improvement (confirmed API-side bottleneck)
- Significantly cleaner codebase
- Better maintainability
- Consistent with actual API behavior

**Location:** `docker/services/ruby/lib/monadic/utils/interaction_utils.rb` (lines ~453-507)

### OpenAI TTS Audio Quality Improvement

**Problem:** `speed` parameter was always sent to OpenAI API, even when user didn't change speed (default `speed=1.0`). This forced speed conversion processing, degrading audio quality especially for `gpt-4o-mini-tts`.

**Root Cause:**
```ruby
# Before (problematic)
val_speed = speed ? speed.to_f : 1.0  # Always set to 1.0
body = {
  "speed" => val_speed,  # Always sent, even for default speed
  ...
}
```

**Solution:**
- Only include `speed` parameter when explicitly set by user AND different from 1.0
- Omit `speed` parameter when user hasn't changed speed
- Allows OpenAI to use optimal processing without speed conversion overhead

```ruby
# After (improved)
body = {
  "input" => text_converted,
  "model" => model,
  "voice" => voice,
  "response_format" => response_format
}

# Only include speed parameter if explicitly set by user
if speed && speed.to_f != 1.0
  body["speed"] = speed.to_f
end
```

**Results:**
- **Noticeable audio quality improvement** (subjective evaluation confirmed)
- gpt-4o-mini-tts now produces higher quality output at default speed
- Consistent with ElevenLabs implementation pattern (only send when needed)
- No functional changes to speed control when user actively adjusts speed

**Impact:**
- Default TTS (no speed change): Better quality, no `speed` parameter sent
- Speed adjusted (e.g., 0.5x, 1.5x): Works as before, `speed` parameter sent

**Location:** `docker/services/ruby/lib/monadic/utils/interaction_utils.rb` (lines ~323-327)

## Safety Improvements (Added 2024-10-12)

### 1. STOP_TTS Thread Cleanup

**Problem:** Stopping TTS only killed main thread, leaving prefetch API request threads running.

**Solution:**
- Store `tts_futures` array in `Thread.current[:tts_futures]`
- STOP_TTS handler kills all prefetch subthreads before killing main thread
- Prevents orphaned threads and wasted API calls

**Location:** Lines 1424-1451, 1567-1568

### 2. Error Handling for Thread#value

**Problem:** Single segment failure would stop entire playback.

**Solution:**
- Wrap `Thread#value` in `begin/rescue` block
- Create error response for failed segments
- Continue to next segment even if one fails
- Handles both API errors and thread kill exceptions

**Location:** Lines 1603-1615

### 3. Graceful Degradation

**Behavior:**
- If segment N fails, segment N+1 still plays
- User sees which segment failed in logs
- STOP_TTS cleanly interrupts prefetch pipeline

## Configuration Options

### ~/monadic/config/env

```bash
# ElevenLabs V3 segment behavior (optional)
ELEVENLABS_V3_COMBINE_SEGMENTS=true  # Disable prefetch (legacy mode)

# Batch processing for TTS+text delivery (optional)
USE_BATCH_PROCESSING=false           # Disable batching

# Debug logging (optional)
EXTRA_LOGGING=true                   # Enable detailed logs
```

## Debug Logging

When `EXTRA_LOGGING=true`, you'll see:

```
ElevenLabs V3: Using segment splitting for prefetch (5 segments)
TTS segment 2 failed with exception: Connection timeout
ElevenLabs V3: Combined all segments into one (legacy mode)
```

## Performance Characteristics

### Without Prefetch (Legacy V3)
- Wait time: Full text generation time
- Example: 30-second text → 30-second wait → playback starts

### With Prefetch (New Default)
- Wait time: First segment generation time only
- Example: 30-second text → 3-second wait → playback starts (remaining segments generate while playing)

### Typical Improvements
- **Time to First Audio**: 5-10x faster for long texts
- **Perceived Latency**: Dramatically reduced
- **User Experience**: Feels nearly instantaneous

## Performance Benchmark Results (2024-10-14)

Comprehensive latency measurements for 116-character test text across all providers:

### TTFB (Time to First Byte) Ranking:
1. **ElevenLabs Flash: 532.5ms** ⚡ Fastest
2. **OpenAI TTS HD: 1334.3ms** (surprisingly faster than standard)
3. **OpenAI TTS: 1913.4ms**
4. **Gemini Flash TTS: 6129.8ms** (11.5x slower than ElevenLabs)

### Total Completion Time:
1. **ElevenLabs Flash: 603.2ms** - Fastest end-to-end
2. **OpenAI TTS HD: 1814.3ms**
3. **OpenAI TTS: 3038.9ms**
4. **Gemini Flash TTS: 6253.9ms**

### Audio File Size:
1. **ElevenLabs Flash: 95.6 KB** - Smallest, optimized compression
2. **OpenAI TTS: 139.7 KB**
3. **OpenAI TTS HD: 140.6 KB** - HD quality with minimal size increase
4. **Gemini Flash TTS: 561.4 KB** - 6x larger than ElevenLabs

### Key Insights:

**ElevenLabs Flash (Best for Low Latency):**
- Fastest TTFB and total time
- Smallest file size
- Excellent for real-time conversational applications
- Name accurately reflects performance ("Flash")

**OpenAI TTS 4o Mini (gpt-4o-mini-tts):**
- Latest and most capable TTS model (benchmarked: 1644ms TTFB)
- **Smallest file size** among OpenAI models: 117.4 KB
- Supports `instructions` parameter for fine control (accent, emotion, tone, speed, whisper, etc.)
- Example: `"instructions": "Speak in a cheerful and positive tone."`
- 11 voices: alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer (5 new voices added)
- **Format recommendation**: Use `wav` or `pcm` for fastest response times (per OpenAI docs)
- **Quality improvement**: `speed` parameter now only sent when user changes speed (better default quality)
- Faster than TTS HD (1644ms vs 1795ms)
- Best choice when you need both quality and instruction control

**OpenAI TTS HD (Best Balance):**
- Faster than standard model (counter-intuitive!)
- Better quality with minimal latency penalty
- Recommended over standard TTS model for general use

**OpenAI TTS (Standard):**
- **Performance varies significantly** (810-1913ms TTFB observed)
- More streaming chunks (313-324) indicates finer-grained streaming
- Sometimes faster than HD due to API-side load balancing
- OpenAI API performance depends on server load and routing

**Gemini Flash TTS (Quality over Speed):**
- Significantly slower (6-7 seconds initial wait)
- Much larger file size (561-579 KB)
- "Flash" name is misleading for TTS performance
- Best suited when quality matters more than latency
- Prefetch optimization is most critical for this provider
- **Investigation (2024-10-14):** Tested both `streamGenerateContent` and `generateContent` endpoints - latency unchanged (~6-7s), confirming API-side bottleneck

### Prefetch Impact:
- These measurements are for single-segment text (116 characters)
- Multi-segment texts benefit dramatically more from prefetch
- Gemini's 6-second wait can be hidden by prefetch for long texts
- ElevenLabs already feels instantaneous even without prefetch

### Recommendations:
- **Absolute fastest**: ElevenLabs Flash (580ms TTFB, 108 KB)
- **Best for instructions**: OpenAI TTS 4o Mini (1644ms TTFB, 117 KB, full prompt control)
- **Best balance**: OpenAI TTS HD (1795ms TTFB, better audio quality)
- **Budget option**: OpenAI TTS Standard (810-1913ms, performance varies)
- **High quality**: Gemini (6-7s TTFB, 559 KB, accept latency trade-off)
- **Fastest format**: Use `wav` or `pcm` (recommended by OpenAI for lowest latency)
- **Enable prefetch**: Critical for Gemini, beneficial for all providers

### Performance Notes:
- OpenAI API latency varies 2-3x depending on load (observed: 810ms to 1913ms for same model)
- First benchmark session typically shows different patterns than subsequent runs
- ElevenLabs Flash consistently delivers fastest and most predictable latency
- Gemini TTS latency unchanged regardless of endpoint (`streamGenerateContent` vs `generateContent`)

### Format Selection by Use Case:
- **Lowest latency**: `wav` or `pcm` (no decoding overhead)
- **General use**: `mp3` (default, good balance)
- **Internet streaming**: `opus` (optimized for low latency streaming)
- **Mobile apps**: `aac` (preferred by iOS/Android)
- **Archival**: `flac` (lossless compression)

## Testing

Tested with:
- ✅ OpenAI TTS (`tts-1`, `tts-1-hd`)
- ✅ Google Cloud TTS (multiple voices)
- ✅ ElevenLabs V3 (new prefetch mode)
- ✅ Gemini TTS (`gemini-flash`, `gemini-pro`)

Benchmark script: `tmp/test_all_tts_latency.rb`

## Known Limitations

1. **Memory Usage**: Long texts with many segments consume memory (mitigated by 2-request limit)
2. **API Rate Limits**: Possible with very frequent requests (unlikely with 2 concurrent)
3. **ElevenLabs V3**: Some users may prefer legacy single-request mode for quality reasons

## Future Improvements

- [ ] Adaptive concurrency based on segment length
- [ ] Provider-specific optimization (e.g., V3 quality vs. speed trade-off)
- [ ] Memory usage monitoring and automatic throttling
- [ ] Caching for frequently used text segments

## Related Files

- `docker/services/ruby/lib/monadic/utils/websocket.rb` - Main implementation
- `docker/services/ruby/apps/*/` - Apps using TTS features
- `docker/services/ruby/public/js/monadic/ui/audio_player.js` - Client-side playback

## See Also

- `docs_dev/websocket_progress_broadcasting.md` - WebSocket communication patterns
- `docs/features/text-to-speech.md` - User-facing TTS documentation
