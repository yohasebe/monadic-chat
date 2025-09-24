# Facade methods for Jupyter Notebook apps
# All Jupyter functionality is already included in MonadicHelper module

require_relative '../../lib/monadic/agents/gpt5_codex_agent'

module JupyterNotebookTools
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

  # Call GPT-5-Codex agent for complex notebook code generation
  def gpt5_codex_agent(task:, notebook_context: nil, cell_content: nil)
    # Build prompt using the shared helper
    prompt = build_codex_prompt(
      task: task,
      context: notebook_context,
      current_code: cell_content
    )

    # Call the shared GPT-5-Codex implementation
    call_gpt5_codex(prompt: prompt, app_name: "JupyterNotebook")
  end
end

class JupyterNotebookOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include JupyterNotebookTools
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

class JupyterNotebookClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

class JupyterNotebookGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

class JupyterNotebookGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

# Shared utilities for Jupyter Notebook apps
module JupyterNotebookShared
  private
  
  def validate_notebook_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end