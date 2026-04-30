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

    SESSION_TOGGLE_KEY = 'library_rag_enabled'

    DISABLED_MESSAGE = "❌ Knowledge Base RAG is disabled for this session. " \
                       "The user can enable it by toggling 'Use Knowledge Base' " \
                       "in the Knowledge Base sidebar panel. Tell the user this " \
                       "and let them re-ask once enabled.".freeze

    # Resolve the session-level toggle. Same fallback chain shared tools
    # use elsewhere: explicit kwarg → @session ivar → Thread-local.
    def self.session_enabled?(session)
      params = (session && (session[:parameters] || session['parameters'])) || {}
      !!params[SESSION_TOGGLE_KEY]
    end

    # The instance-side mixin that apps include. The MDSL `tools` block
    # references the tool name; this method must match the schema declared
    # in MonadicSharedTools::Registry.
    module Tools
      # Search the Knowledge Base for passages relevant to a query.
      # Returns a formatted string ready to inject into the LLM context.
      #
      # The tool is gated by a per-session UI toggle (default OFF). When
      # the toggle is off the tool returns a short instruction so the LLM
      # can pass the message back to the user instead of issuing a
      # confusing search-failed error.
      #
      # The `session:` keyword is auto-injected by every vendor's tool
      # dispatcher (openai_helper / claude_helper / ...) when the method
      # signature declares it. Without that argument the gate would
      # always read nil and the tool would always look disabled, which
      # is exactly the bug we are guarding against by naming the kwarg
      # explicitly here.
      #
      # @param query [String] user query (required)
      # @param top_n [Integer] number of passages to return (default 3)
      # @param session [Hash, nil] auto-injected by the tool dispatcher
      # @return [String] formatted search results or a status message
      def library_search(query:, top_n: DEFAULT_TOP_N, session: nil)
        resolved_session = session || @session || Thread.current[:session]
        unless MonadicSharedTools::LibrarySearch.session_enabled?(resolved_session)
          return MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE
        end

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
    # Each citation uses a markdown link with a custom `mc:conv:` URL
    # scheme so the frontend can intercept clicks and open the
    # Conversation Viewer modal instead of navigating away. The LLM
    # is instructed via the trailing prompt to preserve these links
    # verbatim when summarising — that is what makes a RAG citation
    # round-trip back to the original conversation a single click away.
    def format_results(query, hits)
      return "No matching passages were found in the Knowledge Base for query: #{query.inspect}" if hits.empty?

      lines = []
      lines << "Found #{hits.size} relevant passage#{'s' if hits.size != 1} in the Knowledge Base:"
      lines << ''
      hits.each_with_index do |hit, i|
        cite_title = hit[:conversation_title].to_s.empty? ? '(untitled)' : hit[:conversation_title]
        cite_source = hit[:conversation_source].to_s.empty? ? 'unknown source' : hit[:conversation_source]
        link = "[#{cite_title}](mc:conv:#{hit[:conversation_id]})"
        lines << "[#{i + 1}] From #{link} (#{cite_source})"
        lines << "  speaker_role=#{hit[:speaker_role]} turn=#{hit[:turn_idx]} score=#{format('%.3f', hit[:score])}"
        snippet = hit[:text].to_s.gsub(/\s+/, ' ').strip
        snippet = snippet[0, 480] + (snippet.length > 480 ? '…' : '')
        lines << "  > #{snippet}"
        lines << ''
      end
      lines << '_When citing these passages in your reply, keep the markdown links above as-is so the user can click through to the original conversation._'
      lines.join("\n").strip
    end
  end
end
