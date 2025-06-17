# CONFIG vs ENV Usage Analysis in Monadic Chat

## Summary of Findings

### 1. Inconsistent Access Patterns

#### API Keys
Most vendor helpers use `CONFIG[key] || ENV[key]` pattern (CONFIG first):
- `claude_helper.rb`: `CONFIG["ANTHROPIC_API_KEY"] || ENV["ANTHROPIC_API_KEY"]`
- `gemini_helper.rb`: `CONFIG["GEMINI_API_KEY"] || ENV["GEMINI_API_KEY"]`
- `grok_helper.rb`: `CONFIG["XAI_API_KEY"] || ENV["XAI_API_KEY"]`
- `mistral_helper.rb`: `CONFIG["MISTRAL_API_KEY"] || ENV["MISTRAL_API_KEY"]`
- `perplexity_helper.rb`: `CONFIG["PERPLEXITY_API_KEY"] || ENV["PERPLEXITY_API_KEY"]`
- `deepseek_helper.rb`: `CONFIG["DEEPSEEK_API_KEY"] || ENV["DEEPSEEK_API_KEY"]`

**Exception**: `openai_helper.rb` uses reverse order:
- `ENV["OPENAI_API_KEY"] || CONFIG["OPENAI_API_KEY"]`

### 2. Variables Accessed via Both CONFIG and ENV

| Variable | CONFIG Usage | ENV Usage | Notes |
|----------|--------------|-----------|-------|
| `OPENAI_API_KEY` | monadic.rb, openai_helper.rb | openai_helper.rb, ai_user_agent.rb, text_embeddings.rb | Inconsistent order |
| `ELEVENLABS_API_KEY` | monadic.rb | monadic.rb | Both in same file |
| `TTS_DICT_DATA` | monadic.rb | monadic.rb | Both in same file |
| `EXTRA_LOGGING` | Throughout codebase | monadic.rb initialization | ENV overrides CONFIG |
| `DISTRIBUTED_MODE` | app.rb, dsl.rb, jupyter_helper.rb | app.rb | Complex fallback logic |
| `AI_USER_MAX_TOKENS` | All vendor helpers | second_opinion_agent.rb | Different components |

### 3. Variables Only Accessed via ENV

These are accessed only via ENV, never through CONFIG:
- `WEBSEARCH_MODEL` (websearch_agent.rb, openai_helper.rb)
- `JUPYTER_PORT` (jupyter_helper.rb)
- `PYTHON_PORT` (flask_app_client.rb)
- `AI_USER_MODEL` (second_opinion_agent.rb)
- `MONADIC_DEBUG` (app.rb)
- `DEBUG_TTS` (interaction_utils.rb, websocket.rb)
- `RACK_ENV` (websocket.rb)
- Default model names (`*_DEFAULT_MODEL` in ai_user_agent.rb)

### 4. How CONFIG is Populated

1. CONFIG is initialized with defaults in `monadic.rb`
2. Values from `~/monadic/config/env` file are loaded into CONFIG
3. Some ENV variables can override CONFIG values (e.g., `EXTRA_LOGGING`)

### 5. Specific Issues Found

#### Issue 1: Inconsistent Priority Order
- Most helpers: CONFIG first, ENV as fallback
- OpenAI helper: ENV first, CONFIG as fallback
- This could cause confusion if both are set with different values

#### Issue 2: Mixed Access in Same Component
- `monadic.rb` lines 274-275:
  ```ruby
  elsif tts_dict_data || CONFIG["TTS_DICT_DATA"] || ENV["TTS_DICT_DATA"]
    data_to_process = tts_dict_data || CONFIG["TTS_DICT_DATA"] || ENV["TTS_DICT_DATA"]
  ```

#### Issue 3: DISTRIBUTED_MODE Complex Logic
- Line 80 in app.rb:
  ```ruby
  distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] ? CONFIG["DISTRIBUTED_MODE"] : (ENV["DISTRIBUTED_MODE"] || "off")
  ```
- This checks CONFIG existence, then CONFIG value, then ENV, then defaults to "off"

#### Issue 4: Different Components Use Different Sources
- Vendor helpers use CONFIG["AI_USER_MAX_TOKENS"]
- second_opinion_agent uses ENV["AI_USER_MAX_TOKENS"]
- This could lead to inconsistent behavior

### 6. Recommendations

1. **Standardize Access Order**: All code should use the same priority order (recommend CONFIG first, ENV as override)

2. **Centralize Configuration Access**: Create a helper method like:
   ```ruby
   def get_config(key)
     ENV[key] || CONFIG[key]
   end
   ```

3. **Document Which Variables Should Be in CONFIG vs ENV**:
   - CONFIG: User settings from env file
   - ENV: System/deployment overrides

4. **Fix OpenAI Helper**: Change to match other helpers' pattern

5. **Consolidate AI_USER_MAX_TOKENS Access**: Either always use CONFIG or always use ENV

6. **Consider Moving ENV-Only Variables**: Variables like WEBSEARCH_MODEL that are never in CONFIG could be added to CONFIG loading