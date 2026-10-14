# Reasoning Context and `context_size`

Two different things limit or carry context in OpenAI Responses API requests.

| Name | Where | What it is |
|---|---|---|
| `context_size` | MDSL (`llm` or `features`) | The number of earlier messages sent with a request (the first message plus the last `context_size`) |
| `reasoning_context` | `obj["reasoning_context"]` in `openai_helper.rb` | The last `REASONING_CONTEXT_MAX` (3) reasoning segments of the latest response |

## `reasoning_context`

When a Responses API reply contains reasoning, the OpenAI helper stores up to three reasoning segments in `obj["reasoning_context"]` (as `{type: "reasoning", content: [{type: "output_text", text: …}]}`); a reply without reasoning text removes the key. No code reads `reasoning_context`, and it is not sent in later requests. It is not an MDSL setting.

What is shown in the Thinking panel comes from `reasoning_content` on the message, which merges the reasoning of all tool rounds of the turn (`session[:openai_reasoning]`).

## For App Authors

- Set `reasoning_effort` explicitly where the app needs a specific level; the accepted values come from the model's spec.
- Set `context_size` to the number of earlier messages the app needs.

## Debugging

With `EXTRA_LOGGING=true`, `~/monadic/log/extra.log` has the `Processing responses API query` entries with each request body.
