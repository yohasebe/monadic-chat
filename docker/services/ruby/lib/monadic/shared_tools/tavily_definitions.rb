# frozen_string_literal: true

module Monadic
  module SharedTools
    # Canonical definitions for the Tavily-backed web search tools.
    #
    # Source of truth for:
    #   - The OpenAI-compatible function schemas (tavily_search /
    #     tavily_fetch) that get registered in body["tools"] when a
    #     non-native-search provider has TAVILY_API_KEY configured AND
    #     the user has enabled the web search toggle.
    #   - The system-prompt fragment that nudges the LLM to actually
    #     reach for those tools instead of fabricating answers.
    #
    # Before consolidating here (2026-05-13), each of Cohere /
    # DeepSeek / Mistral / Ollama helpers carried verbatim copies that
    # had drifted in small ways — e.g. Cohere required both `query`
    # AND `n`, while every other helper required only `query`. The
    # divergence was a latent bug source whenever the Tavily tool
    # surface changed.
    #
    # All four Tavily-fallback helpers now alias their local
    # constants to these definitions; a structural spec
    # (`spec/unit/shared_tools/tavily_definitions_spec.rb`) pins the
    # contract so drift cannot creep back in silently.
    module TavilyDefinitions
      TOOLS = [
        {
          type: "function",
          function: {
            name: "tavily_fetch",
            description: "fetch the content of the web page of the given url and return its content.",
            parameters: {
              type: "object",
              properties: {
                url: {
                  type: "string",
                  description: "url of the web page."
                }
              },
              required: ["url"]
            }
          }
        },
        {
          type: "function",
          function: {
            # `n` is intentionally NOT in `required` — Tavily defaults
            # to 3 results when omitted, and forcing models to always
            # supply a count makes them invent arbitrary values (often
            # too large).
            name: "tavily_search",
            description: "search the web for the given query and return the result. the result contains the answer to the query, the source url, and the content of the web page.",
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "query to search for."
                },
                n: {
                  type: "integer",
                  description: "number of results to return (default: 3)."
                }
              },
              required: ["query"]
            }
          }
        }
      ].freeze

      # Prompt design notes:
      # * Kept under ~15 lines so the English instructional text does
      #   not overwhelm the surrounding system prompt's language cues.
      #   Smaller models (e.g. Ollama Qwen3 4B-class) tend to slip
      #   into English responses when buried under long English
      #   instructions — the explicit "respond in the user's
      #   language" line pushes back on that.
      # * "When appropriate" vs the older "MUST always use" — the
      #   strong directive made small models search compulsively even
      #   for trivially answerable questions. The softer phrasing
      #   keeps quality on the bigger models without the
      #   over-triggering tax on smaller ones.
      # * Citation format uses `rel="noopener noreferrer"` so opened
      #   tabs cannot reach `window.opener` (defense-in-depth even
      #   though Monadic Chat's renderer sanitises output).
      PROMPT = <<~TEXT

        IMPORTANT: You have access to web research tools for retrieving up-to-date information.

        Available functions:
        - tavily_search(query, n=3): Search the web. Returns relevant results with source URLs.
        - tavily_fetch(url): Fetch the full content of a specific URL.

        When appropriate, use these tools to ground your answers:
        - The user asks about current events, recent news, or up-to-date information.
        - The user asks about specific named entities (people, companies, products, events).
        - A factual claim needs verification.

        How to use them effectively:
        - Search queries work best in English even when the user writes in another language.
        - ALWAYS respond to the user in the language they used. Do not switch to English just because the search results are in English.
        - Cite sources using HTML anchors: <a href="URL" target="_blank" rel="noopener noreferrer">Title</a>.
        - Use the information you find — do not fabricate when search can confirm.
      TEXT

      # Single source of truth for "is Tavily-backed web search active for this
      # request?". Replaces four subtly-divergent copies that lived in the
      # Cohere / DeepSeek / Mistral / Ollama helpers — notably DeepSeek's bare
      # `CONFIG["TAVILY_API_KEY"]` truthy check, which treated an empty-string
      # key as configured. Centralizing it also makes every Tavily-fallback
      # provider behave identically (important for headless callers that supply
      # the `websearch` flag themselves).
      def self.websearch_requested?(obj)
        return false if !defined?(CONFIG) || CONFIG["TAVILY_API_KEY"].to_s.strip.empty?

        value = obj.is_a?(Hash) || obj.respond_to?(:[]) ? obj["websearch"] : nil
        value == true || value == "true"
      end

      # Names of every tool that performs web search (the web_search_tools group
      # plus the Tavily primitives). Used to gate web search at the execution
      # point so a UI-disabled toggle is honored no matter how the model
      # surfaced the call (schema, or a content-embedded JSON/DSML fallback).
      WEB_SEARCH_TOOL_NAMES = %w[search_web fetch_web_content tavily_search tavily_fetch].freeze

      def self.web_search_tool?(name)
        WEB_SEARCH_TOOL_NAMES.include?(name.to_s)
      end
    end
  end
end
