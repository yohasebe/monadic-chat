# Claude Context Management

The Claude helper sends Anthropic's context editing settings (`context_management`, beta `context-management-2025-06-27`) so that old tool results and thinking blocks are cleared on the server as a conversation grows. The conversation kept by Monadic Chat is not changed.

## When It Is Sent

`claude_helper.rb` adds `context_management` and the beta header when:

- the model has `supports_context_management: true` in `model_spec.js` (`ModelSpec.supports_context_management?`),
- the request is not a tool-result continuation (`role != "tool"`), and
- the app has not set `context_management false`.

## Default Edits

Without an MDSL setting:

| Edit | Added when | Settings |
|---|---|---|
| `clear_thinking_20251015` | Thinking is enabled | `keep: {type: "thinking_turns", value: 1}` |
| `clear_tool_uses_20250919` | Always | `trigger: {type: "input_tokens", value: 100000}`, `keep: {type: "tool_uses", value: 5}`, `clear_at_least: {type: "input_tokens", value: 10000}` |

`clear_thinking` comes first; the API requires that order when both are present.

## MDSL

At the app level (not inside `llm`):

```ruby
context_management do
  edits [
    {
      type: "clear_tool_uses_20250919",
      trigger: { type: "input_tokens", value: 50000 },
      keep: { type: "tool_uses", value: 3 },
      clear_at_least: { type: "input_tokens", value: 15000 },
      exclude_tools: []
    }
  ]
end
```

- A block replaces the default edits entirely; with thinking enabled, add a `clear_thinking_20251015` edit first if it is wanted.
- `context_management false` sends no context editing and no beta header. History is then limited only by `context_size`.

Research Assistant (Claude) uses the settings shown above.

### Edit Options

`clear_tool_uses_20250919`:

| Option | Meaning |
|---|---|
| `trigger` | When clearing starts (`input_tokens` or `tool_uses`) |
| `keep` | Recent tool use/result pairs to keep |
| `clear_at_least` | Minimum tokens to clear |
| `exclude_tools` | Tool names never cleared |
| `clear_tool_inputs` | Also clear tool call inputs (default: results only) |

`clear_thinking_20251015`:

| Option | Meaning |
|---|---|
| `keep` | `{type: "thinking_turns", value: N}` (thinking of the last N assistant turns) or `"all"` |

Clearing changes the prompt prefix, so the prompt cache is written again from the cleared point. Keeping all thinking blocks keeps the cache.

## Response

The API reports what it cleared in `context_management.applied_edits` (type, `cleared_tool_uses` or `cleared_thinking_turns`, `cleared_input_tokens`).

## Related Files

- `public/js/monadic/model_spec.js` (`supports_context_management`)
- `lib/monadic/utils/model_spec.rb` (`supports_context_management?`)
- `lib/monadic/adapters/vendors/claude_helper.rb`
- `lib/monadic/dsl.rb` (`context_management`)
- [Anthropic: Context editing](https://docs.claude.com/en/docs/build-with-claude/context-editing)
