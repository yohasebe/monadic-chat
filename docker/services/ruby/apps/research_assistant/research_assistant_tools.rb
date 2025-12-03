# frozen_string_literal: true

# Facade methods for Research Assistant apps
# Web search is now provided via import_shared_tools :web_search_tools

require_relative '../../lib/monadic/agents/openai_code_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

# Session State tools for Research Assistant
module ResearchAssistantSessionState
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "research_assistant_context"

  # Save research progress and context to session state.
  #
  # @param message [String] Response message to the user
  # @param current_topic [String] The current research topic
  # @param research_topics [Array<String>] Research topics explored
  # @param search_history [Array<String>] Searches performed with brief results
  # @param findings [Array<String>] Key findings and insights
  # @param sources [Array<String>] Sources and citations
  # @param notes [Array<String>] Research notes and observations
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_research_progress(message:, current_topic: nil, research_topics: nil,
                             search_history: nil, findings: nil, sources: nil, notes: nil, session: nil)
    existing = load_research_internal(session)

    context = {
      current_topic: current_topic || existing[:current_topic],
      research_topics: research_topics || existing[:research_topics] || [],
      search_history: search_history || existing[:search_history] || [],
      findings: findings || existing[:findings] || [],
      sources: sources || existing[:sources] || [],
      notes: notes || existing[:notes] || [],
      last_message: message
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load research progress from session state.
  # Called by LLM to check current research state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_research_progress(session: nil)
    default_context = {
      current_topic: nil,
      research_topics: [],
      search_history: [],
      findings: [],
      sources: [],
      notes: [],
      last_message: nil
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Add a finding to the research.
  #
  # @param finding [String] Key finding or insight
  # @param source [String] Source of the finding (optional)
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_finding(finding:, source: nil, session: nil)
    existing = load_research_internal(session)
    entry = source ? "#{finding} [Source: #{source}]" : finding
    all_findings = (existing[:findings] || []) + [entry]
    all_findings = all_findings.uniq

    # Also add source if provided
    all_sources = existing[:sources] || []
    all_sources = (all_sources + [source]).uniq if source

    context = existing.merge(findings: all_findings, sources: all_sources)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add research topics explored.
  #
  # @param topics [Array<String>] Research topics to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_research_topics(topics:, session: nil)
    existing = load_research_internal(session)
    all_topics = (existing[:research_topics] || []) + (topics || [])
    all_topics = all_topics.uniq

    context = existing.merge(research_topics: all_topics)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Record a search performed.
  #
  # @param query [String] The search query
  # @param result_summary [String] Brief summary of results (optional)
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_search(query:, result_summary: nil, session: nil)
    existing = load_research_internal(session)
    entry = result_summary ? "#{query} → #{result_summary}" : query
    all_searches = (existing[:search_history] || []) + [entry]

    context = existing.merge(search_history: all_searches)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add sources/citations.
  #
  # @param sources [Array<String>] Sources to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_sources(sources:, session: nil)
    existing = load_research_internal(session)
    all_sources = (existing[:sources] || []) + (sources || [])
    all_sources = all_sources.uniq

    context = existing.merge(sources: all_sources)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add research notes.
  #
  # @param notes [Array<String>] Notes to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_research_notes(notes:, session: nil)
    existing = load_research_internal(session)
    all_notes = (existing[:notes] || []) + (notes || [])
    all_notes = all_notes.uniq

    context = existing.merge(notes: all_notes)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  private

  # Internal helper to load research as Ruby hash (not JSON string)
  def load_research_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      current_topic: data["current_topic"],
      research_topics: data["research_topics"] || [],
      search_history: data["search_history"] || [],
      findings: data["findings"] || [],
      sources: data["sources"] || [],
      notes: data["notes"] || [],
      last_message: data["last_message"]
    }
  rescue StandardError
    {
      current_topic: nil,
      research_topics: [],
      search_history: [],
      findings: [],
      sources: [],
      notes: [],
      last_message: nil
    }
  end
end

module ResearchAssistantTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::OpenAICodeAgent
  include ResearchAssistantSessionState

  # Call GPT-5-Codex agent for code generation in research context
  def openai_code_agent(task:, research_context: nil, data_structure: nil)
    # Build prompt using the shared helper
    prompt = build_openai_code_prompt(
      task: task,
      context: research_context,
      current_code: data_structure
    )

    # Call the shared GPT-5-Codex implementation
    call_openai_code(prompt: prompt, app_name: "ResearchAssistant")
  end
end

module ResearchAssistantGrokTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::GrokCodeAgent
  include ResearchAssistantSessionState

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

# Base module for providers without code agents
module ResearchAssistantBaseTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include ResearchAssistantSessionState
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
  include ResearchAssistantBaseTools
  include MonadicSharedTools::WebSearchTools
end

class ResearchAssistantGemini < MonadicApp
  include GeminiHelper
  include ResearchAssistantBaseTools
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
  include ResearchAssistantBaseTools
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

class ResearchAssistantMistral < MonadicApp
  include MistralHelper
  include ResearchAssistantBaseTools
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

class ResearchAssistantDeepSeek < MonadicApp
  include DeepSeekHelper
  include ResearchAssistantBaseTools
  include MonadicSharedTools::WebSearchTools
  include TavilyHelper
end

# Ollama doesn't support web search, so no Research Assistant for Ollama
