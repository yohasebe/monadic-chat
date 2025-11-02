# Facade methods for Jupyter Notebook apps
# All Jupyter functionality is already included in MonadicHelper module

require_relative '../../lib/monadic/agents/openai_code_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

module JupyterNotebookTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::OpenAICodeAgent

  # Call GPT-5-Codex agent for complex notebook code generation
  def openai_code_agent(task:, notebook_context: nil, cell_content: nil)
    # Build prompt using the shared helper
    prompt = build_openai_code_prompt(
      task: task,
      context: notebook_context,
      current_code: cell_content
    )

    # Call the shared GPT-5-Codex implementation
    call_openai_code(prompt: prompt, app_name: "JupyterNotebook")
  end
end

module JupyterNotebookGrokTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::GrokCodeAgent

  # Call Grok-Code agent for complex notebook code generation
  def grok_code_agent(task:, notebook_context: nil, cell_content: nil)
    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      context: notebook_context,
      current_code: cell_content
    )

    # Call the shared Grok-Code implementation
    call_grok_code(prompt: prompt, app_name: "JupyterNotebookGrok")
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
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

class JupyterNotebookGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # No additional implementation needed
end

class JupyterNotebookGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include JupyterNotebookGrokTools
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # Now includes Grok-Code agent support
end

# Shared utilities for Jupyter Notebook apps
module JupyterNotebookShared
  private
  
  def validate_notebook_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end