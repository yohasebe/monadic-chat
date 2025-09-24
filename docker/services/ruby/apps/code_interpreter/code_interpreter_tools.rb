# Code Interpreter application tools
# Provides GPT-5-Codex agent integration for complex coding tasks

require_relative '../../lib/monadic/agents/gpt5_codex_agent'

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
    call_gpt5_codex(prompt: prompt, app_name: "CodeInterpreter")
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

# Class definition for Code Interpreter OpenAI with tools
class CodeInterpreterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include CodeInterpreterTools
end