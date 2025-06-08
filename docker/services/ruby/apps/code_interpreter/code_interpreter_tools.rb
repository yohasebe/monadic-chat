# Base classes for all Code Interpreter variants
# Note: This file defines app classes, not tool methods.
# The actual tools are defined via the MDSL files.
class CodeInterpreterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
end

class CodeInterpreterClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
end

class CodeInterpreterGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
end

class CodeInterpreterGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
end

class CodeInterpreterCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
end

class CodeInterpreterDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
end

class CodeInterpreterMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
end

# Private helper methods shared by all Code Interpreter variants
module CodeInterpreterShared
  private
  
  def validate_code_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end