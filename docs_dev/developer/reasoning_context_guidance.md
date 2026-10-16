# Reasoning and `context_size`

In OpenAI Responses API requests:

- `context_size` (MDSL, `llm` or `features`) is the number of earlier messages sent with a request (the first message plus the last `context_size`).
- What is shown in the Thinking panel comes from `reasoning_content` on the message, which merges the reasoning of all tool rounds of the turn (`session[:openai_reasoning]`). Within a turn, an assistant tool-call message carries the reasoning of its round (`reasoning_items`, or else `reasoning_content`) into the next request as `reasoning` input items (`openai_helper.rb`, the Responses API input conversion). Nothing else carries reasoning from one turn into a later one.

## For App Authors

- Set `reasoning_effort` explicitly where the app needs a specific level; the accepted values come from the model's spec.
- Set `context_size` to the number of earlier messages the app needs.

## Debugging

With `EXTRA_LOGGING=true`, `~/monadic/log/extra.log` has the `Processing responses API query` entries with each request body.
