# Facade methods for Jupyter Notebook apps
# All Jupyter functionality is already included in MonadicHelper module

class JupyterNotebookOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
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