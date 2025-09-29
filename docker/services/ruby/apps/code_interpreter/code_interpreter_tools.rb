# Code Interpreter application tools
# Provides GPT-5-Codex agent integration for complex coding tasks

require_relative '../../lib/monadic/agents/gpt5_codex_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

module CodeInterpreterTools
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

  # Call GPT-5-Codex agent for complex Python code generation tasks
  def gpt5_codex_agent(task:, current_code: nil, error_context: nil)
    # Build prompt using the shared helper
    prompt = build_codex_prompt(
      task: task,
      current_code: current_code,
      error_context: error_context
    )

    # Call the shared GPT-5-Codex implementation
    # Code Interpreter might need longer timeout for complex algorithms
    call_gpt5_codex(prompt: prompt, app_name: "CodeInterpreter", timeout: 360)
  end
end

# Private helper methods shared by all Code Interpreter variants
module CodeInterpreterShared
  private

  def validate_code_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end

# Module for Grok Code Interpreter tools
module CodeInterpreterGrokTools
  include MonadicHelper
  include Monadic::Agents::GrokCodeAgent

  # Call Grok-Code agent for complex Python code generation tasks
  def grok_code_agent(task:, current_code: nil, error_context: nil)
    # Immediately send progress notification when tool is called
    # This provides instant feedback to the user
    if respond_to?(:force_progress_message)
      force_progress_message(
        message: "Delegating to Grok-Code specialist agent",
        app_name: "GrokCode",
        i18n_key: "grokCodeDelegating"
      )
    end

    # Debug logging for progress tracking
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[CodeInterpreterGrokTools] Starting grok_code_agent"
      puts "[CodeInterpreterGrokTools] WebSocketHelper defined: #{defined?(::WebSocketHelper)}"
      puts "[CodeInterpreterGrokTools] EventMachine running: #{EventMachine.reactor_running? rescue 'not loaded'}"
      puts "[CodeInterpreterGrokTools] WebSocket session: #{Thread.current[:websocket_session_id] || 'none'}"
    end

    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      current_code: current_code,
      error_context: error_context
    )

    # Call the shared Grok-Code implementation
    # Code Interpreter might need longer timeout for complex algorithms
    result = call_grok_code(prompt: prompt, app_name: "CodeInterpreterGrok", timeout: 360)

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[CodeInterpreterGrokTools] Result received: #{result[:success] ? 'success' : 'failed'}"
    end

    result
  end
end

# Class definition for Code Interpreter OpenAI with tools
class CodeInterpreterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include CodeInterpreterTools
end

# Class definition for Code Interpreter Grok with tools
class CodeInterpreterGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include CodeInterpreterTools
  include CodeInterpreterGrokTools
end