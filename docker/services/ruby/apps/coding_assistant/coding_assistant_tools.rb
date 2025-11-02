# Coding Assistant application tools
# Provides file operations and GPT-5-Codex agent integration

require_relative '../../lib/monadic/agents/openai_code_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

module CodingAssistantTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::OpenAICodeAgent

  # Call GPT-5-Codex agent for coding tasks
  def openai_code_agent(task:, context: nil, files: nil)
    # Build prompt using the shared helper
    prompt = build_openai_code_prompt(
      task: task,
      context: context,
      files: files
    )

    # Call the shared GPT-5-Codex implementation
    call_openai_code(prompt: prompt, app_name: "CodingAssistant")
  end
end

# Module for Grok Coding Assistant tools
module CodingAssistantGrokTools
  include MonadicHelper
  include Monadic::Agents::GrokCodeAgent

  # Call Grok-Code agent for coding tasks
  def grok_code_agent(task:, context: nil, files: nil)
    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      context: context,
      files: files
    )

    # Call the shared Grok-Code implementation
    call_grok_code(prompt: prompt, app_name: "CodingAssistantGrok")
  end
end

# Class definition for Coding Assistant with tools
class CodingAssistantOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include CodingAssistantTools
end

class CodingAssistantGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include CodingAssistantTools
  include CodingAssistantGrokTools
end

# Other Coding Assistant variants (file operations only, no code agents)
class CodingAssistantClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class CodingAssistantGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class CodingAssistantMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class CodingAssistantDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class CodingAssistantCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class CodingAssistantPerplexity < MonadicApp
  include PerplexityHelper if defined?(PerplexityHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end