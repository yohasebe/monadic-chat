# OpenAI Code Agent

`Monadic::Agents::OpenAICodeAgent` (`lib/monadic/agents/openai_code_agent.rb`) lets an OpenAI app hand a coding task to OpenAI's code model through the app's own `OpenAIHelper#api_request`. The Grok and Claude variants have their own agents (`grok_code_agent.rb`, `claude_code_agent.rb`).

## Apps

`openai_code_agent` is a tool of the OpenAI variants of Coding Assistant, Code Interpreter, Jupyter Notebook, Research Assistant and Auto Forge. Each app's tools module defines the method with its own parameters (for example `task:`, `context:`, `files:` in Coding Assistant; `task:`, `current_code:`, `error_context:` in Code Interpreter) and builds the prompt with `build_openai_code_prompt`.

## `build_openai_code_prompt(task:, **options)`

Appends to `task`, when given:

- `current_code` in a code block;
- `error_context` ("Error to fix");
- `files`: at most 3 files, the first 1000 characters of each, with their path;
- `context`.

## `call_openai_code(prompt:, app_name: nil, timeout: nil, model: nil, &block)`

1. Fails with `OpenAIHelper not available` when the class has no `api_request`, and with an access message when `OPENAI_API_KEY` is empty (`has_openai_code_access?`).
2. Model: the `model` argument, else `@context[:agents][:code_generator]`, else `ENV["OPENAI_CODE_MODEL"]`, else `ModelSpec.default_code_model("openai")`.
3. Builds a one-message session (`build_session`): the message uses the `text` field, the parameters set the output-token limit to 128000 and `temperature` to 0.0.
4. Calls `api_request("user", session, call_depth: 0)` inside `Timeout.timeout`. The timeout is the argument, else `OPENAI_CODE_TIMEOUT`, else 1200 seconds.
5. Returns `{code:, success: true, model:}`, or `{error:, success: false}` (with `timeout: true` and a suggestion on timeout).

`OpenAIHelper` sends the request to the Responses API because the model's `model_spec.js` entry says so.

## Progress

When a block is given and the timeout is over 120 seconds, a thread sends `step_progress` fragments (steps in `OPENAI_CODE_STEPS`) every `OPENAI_CODE_PROGRESS_INTERVAL` seconds (60) to the session's WebSocket. `OPENAI_CODE_PROGRESS_ENABLED=false` turns it off. The thread is stopped when the call ends.

## Related Documentation

- `docs_dev/auto_forge_internals.md`
- `docs_dev/websocket_progress_broadcasting.md`
