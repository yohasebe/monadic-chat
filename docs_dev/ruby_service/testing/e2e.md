# End-to-End (E2E) Tests

The specs in `docker/services/ruby/spec/e2e/` exercise the local server through its WebSocket without calling provider APIs. Provider behavior is covered by the integration specs ([integration.md](integration.md)).

## Files

| File | Contents |
|---|---|
| `jupyter_notebook_grok_spec.rb` | Jupyter operations run locally |
| `monadic_context_display_spec.rb` | Display of monadic context, with mock responses |
| `e2e_helper.rb` | `wait_for_server`, `create_websocket_connection`, `send_chat_message`, `wait_for_response`, `extract_ai_response`, `tool_used?`, `check_containers_running` |
| `validation_helper.rb` | Response checks such as `valid_response?`, `code_execution_attempted?`, `system_error?`, `web_search_performed?` |
| `e2e_retry_helper.rb`, `pdf_upload_helper.rb`, `shared_examples/` | Retry helper, PDF upload helper, shared examples |
| `run_e2e_tests.sh` | Starts the Python, Qdrant and Selenium containers that are missing, then runs the specs |

## Running

From the repository root:

```bash
rake spec_e2e:jupyter_notebook
rake spec_e2e:monadic_context
```

From `docker/services/ruby`:

```bash
./spec/e2e/run_e2e_tests.sh all               # or jupyter_notebook, monadic_context
bundle exec rspec spec/e2e/monadic_context_display_spec.rb
```

The specs need the server on `localhost:4567` and the containers they use; they skip when these are not available. No provider API key is needed.

## Writing a Spec

```ruby
require_relative "e2e_helper"

RSpec.describe "Feature E2E", type: :e2e do
  include E2EHelper

  before(:all) do
    skip "containers not running" unless check_containers_running
    skip "server not running" unless wait_for_server
  end

  it "completes the workflow" do
    ws = create_websocket_connection
    send_chat_message(ws, "Your message", app: "AppName")
    response = wait_for_response(ws)
    expect(valid_response?(response)).to be true
    ws[:client].close
  end
end
```

Check behavior (a reply, a tool attempt) rather than exact text, and skip on `system_error?`.
