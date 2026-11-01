# Streaming Rules for Vendor Helpers

Rules that the streaming code of the vendor helpers (`lib/monadic/adapters/vendors/`) follows.

## Reading the Response Body

- Iterate the `http` gem's response body with `res.each do |chunk| … end` and force the chunk to UTF-8. `HTTP::Response::Body` has no `each_line`.
- Pass the body object to the processing method. `res.body.to_s` reads the whole response before anything is shown; use it only for non-streaming calls and error bodies.

## Fragments

A text fragment is sent to the UI as:

```ruby
{ "type" => "fragment", "content" => fragment, "sequence" => n, "timestamp" => Time.now.to_f, "is_first" => n == 0 }
```

`sequence` starts at 0 and grows by one per fragment. `ws-fragment-handler.js` skips a fragment whose `sequence` is not larger than the last one it processed (falling back to `index`, then the timestamp, when `sequence` is missing). `clear_fragments` resets the counter between tool rounds.

The final message is rendered again from the full response, so the streamed text only has to be readable while it arrives.

## Provider Notes

- **Anthropic**: `content_block_stop` adds nothing to the stream. Web search answers come in many content blocks, and a separator per block would break the text.
- **DeepSeek**: once the accumulated content contains DSML, or a fenced JSON Tavily call, the following fragments are held back and the content is handled after the stream (see [deepseek_architecture.md](vendors/deepseek_architecture.md)). Fragments are also held back in JSON mode.
- **Thinking**: thinking and reasoning text is sent as `thinking` / `reasoning` messages, not as fragments (see [thinking_reasoning_display.md](thinking_reasoning_display.md)).

## Debugging

1. Set `EXTRA_LOGGING=true` in `~/monadic/config/env`.
2. Check that chunks arrive and that fragments are sent (log before `block&.call`).
3. In the browser console, set `window.debugFragments = true` to log sequence gaps and skipped fragments.

| Symptom | Usual cause |
|---|---|
| No streaming, final answer correct | A condition holds back every fragment |
| Extra blank lines while streaming | Separators sent per content block |
| `NoMethodError` on the body | `each_line` or another method the body lacks |
