# Ollama Tool Calling: Bug History & Lessons

## TL;DR

From the time Ollama's `tools` parameter was added to `ollama_helper.rb` until 2026-04-05, **tool calling was completely non-functional** for every Ollama app in Monadic Chat. Models never saw tool definitions, so they hallucinated responses instead of calling tools.

The bug survived code review, unit tests, and months of production use.

## The Bug

`format_tools_for_ollama` accepted `Array` and `Hash` inputs but returned `[]` for `String` inputs:

```ruby
def format_tools_for_ollama(tools_config)
  tools = case tools_config
          when Array
            tools_config
          when Hash
            tools_config["function_declarations"] || []
          else
            []  # ← String dropped here
          end
  # ...
end
```

At runtime, `obj["tools"]` was **always a JSON string** because `app_data.rb:78-82` serializes the tools array before sending it over WebSocket:

```ruby
elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
  apps[k][p] = m.to_json  # ← tools becomes a String here
```

So every tool call was silently dropped before reaching Ollama.

## Why Ollama Only?

Every other vendor helper (Claude, OpenAI, Gemini, Mistral, Grok, Perplexity, DeepSeek, Cohere) had explicit `is_a?(String)` / `JSON.parse` handling before the `case` dispatch. Example from `claude_helper.rb:619-621`:

```ruby
tools_param = obj["tools"]
if tools_param.is_a?(String)
  begin
    tools_param = JSON.parse(tools_param)
  # ...
```

Ollama's helper was missing this defensive parse. Unit tests exercised `Array`/`Hash` inputs directly (which worked), so the gap was invisible.

## The Fix

Added JSON-string parsing at the top of `format_tools_for_ollama` (matching the pattern used by other vendors). Commit: `3f42508b`.

## How It Was Discovered

A user requested "Please list the files in the shared folder" on Chat Plus (Ollama). The model returned a plausible but entirely fabricated file list (`report.pdf`, `data.csv`, `notes.txt`, `project_plan.md`). The user noticed these didn't match the actual shared folder contents.

Diagnosis path:
1. Ruled out "weak model" by running `curl /api/chat` with tools directly against Ollama — Ollama returned a correct `tool_calls` array.
2. Traced Monadic Chat's tool-building path → found the type mismatch between `app_data.rb` (emits JSON string) and `format_tools_for_ollama` (expected Array/Hash).

## Lessons

### 1. Integration gaps are invisible to unit tests

Each layer tested in isolation looked fine:
- `app_data.rb`: tests verified correct JSON serialization ✓
- `format_tools_for_ollama`: tests verified Array/Hash formatting ✓
- `api_request`: tests verified body construction ✓

The **handoff between layers** was never exercised. An integration test that simulated the real runtime path (WebSocket JSON string → helper) would have caught it.

### 2. "Tool calling is implemented" can be a false claim

Code review and grep both suggested tools were wired up. A richer status would be: *"tool wiring exists; last verified in production: never"*.

### 3. Cross-provider consistency audits are high-ROI

All other helpers had the same defensive parse. Auditing once for this pattern would have identified the gap immediately. Consider a periodic cross-vendor pattern audit.

## Prevention

- Add an integration test that feeds `{"tools" => tools_array.to_json, ...}` to `api_request` and asserts the outgoing request body contains tool definitions.
- When any vendor helper adds new parameter handling, verify the same parameter is handled in every other vendor helper with the same input shape.
- Prefer "one true input shape" at layer boundaries — the `app_data.rb` → helper contract should be explicit, not emergent.

## Cross-Provider Audit (2026-04-05)

After fixing Ollama, we audited every vendor helper for the same class of bug:

| Provider | `obj["tools"]` handling | Status |
|----------|-------------------------|--------|
| Claude | explicit `is_a?(String)` → `JSON.parse` | ✅ handles strings |
| Mistral | explicit `is_a?(String)` → `JSON.parse` | ✅ handles strings |
| OpenAI | explicit `is_a?(String)` → `JSON.parse` | ✅ handles strings |
| Gemini | `case` with `when String` branch | ✅ handles strings |
| Grok | used only as boolean flag; tools built from `app_tools` (Ruby objects) | ✅ no parse needed |
| Cohere | used only as boolean flag; tools built from `app_tools` | ✅ no parse needed |
| Perplexity | used only as boolean flag; tools built from `app_tools` | ✅ no parse needed |
| **Ollama** | parsed `String` (Array/Hash only), silently dropped strings | 🔴 broken → fixed |

Two architectural patterns exist:
1. **String-parsing** (Claude/Mistral/OpenAI/Gemini): reads `obj["tools"]` directly as the tool source, parses JSON when needed
2. **Flag-only** (Grok/Cohere/Perplexity): uses `obj["tools"]` as a boolean indicator, builds the actual tool list from `app_tools` (the already-parsed `APPS[app].settings["tools"]`)

Ollama followed pattern (1) but missed the string-parse step. The fix applied the same defensive parse the other pattern-1 providers have.

## Related Commit

- `3f42508b` — Parse JSON string tools in Ollama helper so tool calls actually reach the model
