# frozen_string_literal: true


# Shared Library Search tool for Monadic Chat
# Exposes the project-wide Knowledge Base (Library) as a retrieval tool
# that any app can import via `imported_tool_groups [:library_search]`.
#
# Every app searches every entry (the Knowledge Base is one shelf). The
# user also has to flip the per-session RAG toggle in the Knowledge Base
# sidebar before this tool will run at all (default OFF).
#
# Available tools:
#   - library_search: cascade retrieval (summaries → turns) returning
#     turn-level passages with conversation citations.

require 'monadic/library'
require 'monadic/library/readings'
require_relative '../utils/degradation_notifier'
require_relative '../workbench/put'
require_relative '../workbench/channel'

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

    NO_RECORD_MESSAGE = "❌ The Knowledge Base was not searched: what is read is shown to the user, " \
                        "and this reply has no chat to show it in.".freeze

    DISABLED_MESSAGE = "❌ Knowledge Base RAG is disabled for this session. " \
                       "The user can enable it by toggling 'Use Knowledge Base' " \
                       "in the Knowledge Base sidebar panel. Tell the user this " \
                       "and let them re-ask once enabled.".freeze

    # Resolve the session-level toggle. Same fallback chain shared tools
    # use elsewhere: explicit kwarg → @session ivar → Thread-local.
    def self.session_enabled?(session)
      params = (session && (session[:parameters] || session['parameters'])) || {}
      value = params[SESSION_TOGGLE_KEY]
      value == true || value.to_s == 'true'
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
      # @param content_type [String, nil] narrow to a specific content_type
      #   from the inventory (e.g. "conversation", "pdf", "document",
      #   "markdown", "code"). Optional.
      # @param source [String, nil] narrow to a specific source key from the
      #   inventory (e.g. "monadic-chat", "ted-talk"). Optional.
      # @param session [Hash, nil] auto-injected by the tool dispatcher
      # @return [String] formatted search results or a status message
      def library_search(query:, top_n: DEFAULT_TOP_N,
                         content_type: nil, source: nil, session: nil, workbench: nil)
        resolved_session = session || @session || Thread.current[:session]
        unless MonadicSharedTools::LibrarySearch.session_enabled?(resolved_session)
          return MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE
        end
        # What is read is recorded for the reply's message and shown to the
        # user: a reply with no chat to record it in reads nothing.
        return MonadicSharedTools::LibrarySearch::NO_RECORD_MESSAGE unless workbench

        store = MonadicSharedTools::LibrarySearch.default_store
        payload_filter = MonadicSharedTools::LibrarySearch.build_payload_filter(
          content_type: content_type, source: source
        )
        hits = Monadic::Library::Retriever.cascade_search(
          query, store: store,
          top_n: top_n.to_i.clamp(1, 10),
          payload_filter: payload_filter
        )
        reading = MonadicSharedTools::LibrarySearch.reading_of(query, hits)
        unless Monadic::Library::Readings.add(workbench.request_id, workbench.chat_id, reading, session: workbench.session)
          return MonadicSharedTools::LibrarySearch::NO_RECORD_MESSAGE
        end

        MonadicSharedTools::LibrarySearch.place(workbench, reading)
        # A chat that hides its words hides them in what a tool returns as
        # it sends it.
        MonadicSharedTools::LibrarySearch.format_results(query, hits, reading)
      rescue StandardError => e
        "❌ Knowledge Base search failed: #{e.message}"
      end
    end

    # Compose an optional Qdrant payload filter from the LLM-supplied
    # `content_type` / `source` narrowing parameters. Returns nil when
    # neither was supplied so cascade_search treats it as "no extra
    # filter". Empty / blank values are normalised to nil so the LLM
    # passing "" by accident does not collapse the result set.
    def build_payload_filter(content_type: nil, source: nil)
      clauses = []
      ct = content_type.to_s.strip
      src = source.to_s.strip
      clauses << { key: 'content_type', match: { value: ct } } unless ct.empty?
      clauses << { key: 'source', match: { value: src } } unless src.empty?
      return nil if clauses.empty?

      { must: clauses }
    end

    # Default Store factory. Tests can stub this to inject a fake store.
    def default_store
      Monadic::Library::Store.new
    end

    SNIPPET_CHARS = 480

    # A hit's text as the model is given it: one line, at most SNIPPET_CHARS.
    def snippet(hit)
      text = hit[:text].to_s.gsub(/\s+/, ' ').strip
      text.length > SNIPPET_CHARS ? "#{text[0, SNIPPET_CHARS]}…" : text
    end

    def title_of(hit)
      hit[:conversation_title].to_s.empty? ? '(untitled)' : hit[:conversation_title].to_s
    end

    # The record of a search (Monadic::Library::Readings): the excerpts
    # exactly as the model is given them, each with its id.
    def reading_of(query, hits)
      {
        'id' => Monadic::Library::Readings.reading_id,
        'query' => query.to_s,
        'excerpts' => hits.map do |hit|
          { 'id' => Monadic::Library::Readings.excerpt_id, 'conversation_id' => hit[:conversation_id].to_s,
            'title' => title_of(hit), 'source' => hit[:conversation_source].to_s,
            'turn' => hit[:turn_idx], 'text' => snippet(hit) }
        end
      }
    end

    # The excerpts, as a Markdown file of the chat's folder shown on the work
    # screen (Monadic::Workbench::Put). A search with none is recorded on its
    # message only. A copy that cannot be put is left out: the record stays.
    def place(workbench, reading)
      return if reading['excerpts'].empty?

      result = Monadic::Workbench::Put.run(workbench, name: "library-#{reading['id']}.md", content: reading_markdown(reading))
      Monadic::Library::Readings.placed(workbench.request_id, reading['id'], result[:path])
      Monadic::Workbench::Channel.changed(workbench.chat_id) if result[:shown]
    rescue Monadic::Workbench::Put::Refused
      nil
    end

    # What a reading's copy on the work screen says: the search and its
    # excerpts as quotations (what a passage holds is not the page's own
    # markup).
    def reading_markdown(reading)
      lines = ["# Library: #{reading['query'].to_s.gsub(/\s+/, ' ').strip}", '']
      reading['excerpts'].each_with_index do |excerpt, i|
        source = excerpt['source'].to_s.empty? ? '' : " (#{excerpt['source']})"
        lines << "## #{i + 1}. #{excerpt['title']}#{source}"
        lines << ''
        lines << "> #{excerpt['text'].gsub('>', '&gt;')}"
        lines << ''
      end
      lines.join("\n")
    end

    # Format Retriever hits as a compact, citation-ready text block. Each
    # excerpt is linked as `mc:read:<excerpt id>` (Readings.link): the page
    # opens what the reply cites from it, and the reply's message marks
    # the excerpts its text links to.
    def format_results(query, hits, reading)
      return "No matching passages were found in the Knowledge Base for query: #{query.inspect}" if hits.empty?

      lines = []
      lines << "Found #{hits.size} relevant passage#{'s' if hits.size != 1} in the Knowledge Base (shown to the user in the work screen):"
      lines << ''
      hits.each_with_index do |hit, i|
        excerpt = reading['excerpts'][i]
        cite_source = hit[:conversation_source].to_s.empty? ? 'unknown source' : hit[:conversation_source]
        link = "[#{excerpt['title']}](#{Monadic::Library::Readings.link(excerpt['id'])})"
        lines << "[#{i + 1}] From #{link} (#{cite_source})"
        lines << "  speaker_role=#{hit[:speaker_role]} turn=#{hit[:turn_idx]} score=#{format('%.3f', hit[:score])}"
        lines << "  > #{excerpt['text']}"
        lines << ''
      end
      lines << '_When citing these passages in your reply, keep the markdown links above as-is so the user can open the passage you cite._'
      lines.join("\n").strip
    end
  end
end
