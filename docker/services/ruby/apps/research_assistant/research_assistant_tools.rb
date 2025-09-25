# Facade methods for Research Assistant apps
# Provides clear interfaces for WebSearchAgent functionality

require_relative '../../lib/monadic/agents/gpt5_codex_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

module ResearchAssistantTools
  include MonadicHelper
  include WebSearchAgent
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
  include WebSearchAgent
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
  include WebSearchAgent
  include ResearchAssistantTools
  
  # Performs web search using native OpenAI search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantClaude < MonadicApp
  include ClaudeHelper
  include WebSearchAgent
  
  # Performs web search using native Claude search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantGemini < MonadicApp
  include GeminiHelper
  include WebSearchAgent
  
  # Performs web search using native Google search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantGrok < MonadicApp
  include GrokHelper
  include WebSearchAgent
  include ResearchAssistantGrokTools

  # Performs web search using native Grok Live Search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?

    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantCohere < MonadicApp
  include CohereHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantMistral < MonadicApp
  include MistralHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
  
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantDeepSeek < MonadicApp
  include DeepSeekHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantPerplexity < MonadicApp
  include PerplexityHelper
  include WebSearchAgent
  # Perplexity has built-in web search, no need for Tavily
end

# Ollama doesn't support web search, so no Research Assistant for Ollama