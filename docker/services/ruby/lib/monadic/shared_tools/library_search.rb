# frozen_string_literal: true

# Shared Library Search tool for Monadic Chat
# Exposes the project-wide Knowledge Base (Library) as a retrieval tool
# that any app can import via `imported_tool_groups [:library_search]`.
#
# Visibility filter is enforced on the Store side: scope :external means
# only conversations marked `shareable` are returned; `personal` data
# stays inside the Knowledge Base UI.
#
# Available tools:
#   - library_search: cascade retrieval (summaries → turns) returning
#     turn-level passages with conversation citations.

require 'monadic/library'

module MonadicSharedTools
  module LibrarySearch
    module_function

    DEFAULT_TOP_N = 3

    # Returns true when the Library subsystem can plausibly serve a query
    # right now. We check (a) the schema/store classes are loadable, and
    # (b) the embeddings service answers a health probe. The session_id
    # gate (env + per-session toggle) is enforced by the registry layer
    # via Progressive Tool Disclosure, not here.
    def available?
      defined?(Monadic::Library::Store) &&
        Monadic::Embeddings.default_client.respond_to?(:health) &&
        Monadic::Embeddings.default_client.health
    rescue StandardError
      false
    end

    # The instance-side mixin that apps include. The MDSL `tools` block
    # references the tool name; this method must match the schema declared
    # in MonadicSharedTools::Registry.
    module Tools
      # Search the Knowledge Base for passages relevant to a query.
      # Returns a formatted string ready to inject into the LLM context.
      #
      # @param query [String] user query (required)
      # @param top_n [Integer] number of passages to return (default 3)
      # @return [String] formatted search results or a no-result message
      def library_search(query:, top_n: DEFAULT_TOP_N)
        store = MonadicSharedTools::LibrarySearch.default_store
        hits = Monadic::Library::Retriever.cascade_search(
          query, store: store, scope: :external,
          top_n: top_n.to_i.clamp(1, 10)
        )
        MonadicSharedTools::LibrarySearch.format_results(query, hits)
      rescue StandardError => e
        "❌ Knowledge Base search failed: #{e.message}"
      end
    end

    # Default Store factory. Tests can stub this to inject a fake store.
    def default_store
      Monadic::Library::Store.new
    end

    # Format Retriever hits as a compact, citation-ready text block.
    def format_results(query, hits)
      return "No matching passages were found in the Knowledge Base for query: #{query.inspect}" if hits.empty?

      lines = []
      lines << "Found #{hits.size} relevant passage#{'s' if hits.size != 1} in the Knowledge Base:"
      lines << ''
      hits.each_with_index do |hit, i|
        cite_title = hit[:conversation_title].to_s.empty? ? '(untitled)' : hit[:conversation_title]
        cite_source = hit[:conversation_source].to_s.empty? ? 'unknown source' : hit[:conversation_source]
        lines << "[#{i + 1}] From \"#{cite_title}\" (#{cite_source}, conversation_id: #{hit[:conversation_id]})"
        lines << "  speaker_role=#{hit[:speaker_role]} turn=#{hit[:turn_idx]} score=#{format('%.3f', hit[:score])}"
        snippet = hit[:text].to_s.gsub(/\s+/, ' ').strip
        snippet = snippet[0, 480] + (snippet.length > 480 ? '…' : '')
        lines << "  > #{snippet}"
        lines << ''
      end
      lines.join("\n").strip
    end
  end
end
