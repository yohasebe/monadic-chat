# Facade methods for Research Assistant apps
# Web search is now provided via import_shared_tools :web_search_tools

require_relative '../../lib/monadic/agents/gpt5_codex_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

module ResearchAssistantTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::GPT5CodexAgent

  # Call GPT-5-Codex agent for code generation in research context
  def gpt5_codex_agent(task:, research_context: nil, data_structure: nil)
    # Build prompt using the shared helper
    prompt = build_codex_prompt(
      task: task,
      context: research_context,
      current_code: data_structure
    )

    # Call the shared GPT-5-Codex implementation
    call_gpt5_codex(prompt: prompt, app_name: "ResearchAssistant")
  end
end

module ResearchAssistantGrokTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::GrokCodeAgent

  # Call Grok-Code agent for code generation in research context
  def grok_code_agent(task:, research_context: nil, data_structure: nil)
    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      context: research_context,
      current_code: data_structure
    )

    # Call the shared Grok-Code implementation
    call_grok_code(prompt: prompt, app_name: "ResearchAssistantGrok")
  end
end

class ResearchAssistantOpenAI < MonadicApp
  include OpenAIHelper
  include ResearchAssistantTools
  include MonadicSharedTools::WebSearchTools

  # Request access to a locked tool (Progressive Tool Disclosure)
  # @param tool_name [String] Name of the tool to unlock
  # @return [String] Confirmation message
  def request_tool(tool_name:)
    "Tool '#{tool_name}' has been unlocked. You can now use it in your next function call."
  end
end

class ResearchAssistantClaude < MonadicApp
  include ClaudeHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::WebSearchTools
end

class ResearchAssistantGemini < MonadicApp
  include GeminiHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::WebSearchTools
end

class ResearchAssistantGrok < MonadicApp
  include GrokHelper
  include ResearchAssistantGrokTools
  include MonadicSharedTools::WebSearchTools

  # Request access to a locked tool (Progressive Tool Disclosure)
  # @param tool_name [String] Name of the tool to unlock
  # @return [String] Confirmation message
  def request_tool(tool_name:)
    "Tool '#{tool_name}' has been unlocked. You can now use it in your next function call."
  end
end

class ResearchAssistantCohere < MonadicApp
  include CohereHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

class ResearchAssistantMistral < MonadicApp
  include MistralHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

class ResearchAssistantDeepSeek < MonadicApp
  include DeepSeekHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

# Ollama doesn't support web search, so no Research Assistant for Ollama
