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
    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      current_code: current_code,
      error_context: error_context
    )

    # Call the shared Grok-Code implementation
    # Code Interpreter might need longer timeout for complex algorithms
    call_grok_code(prompt: prompt, app_name: "CodeInterpreterGrok", timeout: 360)
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