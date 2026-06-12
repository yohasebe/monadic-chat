# frozen_string_literal: true

# Shared Library Search tool for Monadic Chat
# Exposes the project-wide Knowledge Base (Library) as a retrieval tool
# that any app can import via `imported_tool_groups [:library_search]`.
#
# Scope is per-app. The Retriever filters on `scope_app IN
# [current_app, "Global"]`, so an entry saved while ChatOpenAI was active
# is not visible to ChatClaude — provider variants are separate scopes.
# The "Global" sentinel opts an entry in to cross-app retrieval. The user
# also has to flip the per-session RAG toggle in the Knowledge Base
# sidebar before this tool will run at all (default OFF).
#
# Available tools:
#   - library_search: cascade retrieval (summaries → turns) returning
#     turn-level passages with conversation citations.

require 'monadic/library'
require_relative '../utils/degradation_notifier'

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
      # @param content_type [String, nil] narrow to a specific content_type
      #   from the inventory (e.g. "conversation", "pdf", "document",
      #   "markdown", "code"). Optional.
      # @param source [String, nil] narrow to a specific source key from the
      #   inventory (e.g. "monadic-chat", "ted-talk"). Optional.
      # @param session [Hash, nil] auto-injected by the tool dispatcher
      # @return [String] formatted search results or a status message
      def library_search(query:, top_n: DEFAULT_TOP_N,
                         content_type: nil, source: nil, session: nil)
        resolved_session = session || @session || Thread.current[:session]
        unless MonadicSharedTools::LibrarySearch.session_enabled?(resolved_session)
          return MonadicSharedTools::LibrarySearch::DISABLED_MESSAGE
        end

        # Resolve the requesting app's class name from the session so the
        # cascade can filter on `scope_app IN [app_name, "Global"]`.
        # Conversations saved while another app was active are
        # intentionally invisible here — provider variants are separate
        # scopes ("ChatOpenAI" cannot see "ChatClaude" entries) and
        # shareable knowledge artifacts use the literal "Global" sentinel
        # to opt in to cross-app retrieval.
        app_name = MonadicSharedTools::LibrarySearch.resolve_app_name(resolved_session)

        store = MonadicSharedTools::LibrarySearch.default_store
        payload_filter = MonadicSharedTools::LibrarySearch.build_payload_filter(
          content_type: content_type, source: source
        )
        hits = Monadic::Library::Retriever.cascade_search(
          query, store: store, app_name: app_name,
          top_n: top_n.to_i.clamp(1, 10),
          payload_filter: payload_filter
        )
        out = MonadicSharedTools::LibrarySearch.format_results(query, hits)
        MonadicSharedTools::LibrarySearch.apply_privacy(out, resolved_session)
      rescue StandardError => e
        "❌ Knowledge Base search failed: #{e.message}"
      end
    end

    # Returned to the LLM in place of search results when the user has the
    # Privacy Filter ON but masking is unavailable. Fail-closed: unmasked
    # snippets must never reach the provider in that state.
    WITHHELD_MESSAGE = "❌ Knowledge Base results withheld: privacy masking is " \
                       "currently unavailable, so unmasked content cannot be " \
                       "sent to the provider. Tell the user the Privacy Filter " \
                       "service appears to be down and that they can retry " \
                       "once it recovers (or search again with the Privacy " \
                       "Filter toggled off if they accept sending unmasked " \
                       "content).".freeze

    # Mask PII in a tool-result payload before the LLM ever sees it.
    # Knowledge Base entries are stored unmasked (the Save dialog warns
    # the user about this), so retrieval would otherwise re-expose any
    # PII present in saved conversations to the next LLM request — even
    # when the user has Privacy Filter ON for the current session.
    #
    # The session-level Privacy Pipeline is created lazily by the vendor
    # helper at request build time. By the time a tool call fires it has
    # already been instantiated and is reachable via session[:_privacy_pipeline].
    # We register the search snippets there so that any placeholder the
    # LLM echoes back gets restored by streaming_handler against the
    # same registry — round-trip is symmetric without further wiring.
    #
    # Failure policy is fail-closed, matching the pipeline's own
    # `on_failure: :block` default: when masking raises, the snippets are
    # withheld from the LLM entirely and the degradation is reported. The
    # previous behavior (return the original text) silently sent unmasked
    # PII to the provider exactly when the privacy backend was broken.
    def apply_privacy(text, session)
      return text unless text.is_a?(String) && !text.empty?

      pipeline = session && (session[:_privacy_pipeline] || session['_privacy_pipeline'])
      return text unless pipeline.respond_to?(:enabled?) && pipeline.enabled?

      require_relative '../utils/privacy/types'
      raw = Monadic::Utils::Privacy::RawMessage.new(text, 'tool', {})
      pipeline.before_send_to_llm(raw).text
    rescue StandardError => e
      Monadic::Utils::DegradationNotifier.report(
        component: 'privacy',
        message: "masking failed during Knowledge Base search; results were withheld from the LLM (#{e.message})",
        severity: :error
      )
      WITHHELD_MESSAGE
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

    # Pull the requesting app's class name out of the session params.
    # Returns nil when the session is missing or app_name is empty so
    # cascade_search falls back to "no scope filter" — useful for tests
    # and for the Knowledge Base app itself, which legitimately wants to
    # see the full library when the user explicitly asked it to.
    def resolve_app_name(session)
      params = (session && (session[:parameters] || session['parameters'])) || {}
      v = params['app_name'] || params[:app_name]
      v = v.to_s.strip
      v.empty? ? nil : v
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
