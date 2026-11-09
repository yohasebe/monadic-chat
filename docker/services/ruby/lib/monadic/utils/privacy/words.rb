# frozen_string_literal: true

require_relative 'word_table'
require_relative 'outbound'
require_relative '../../workspace/chats'
require_relative '../../workspace/ids'

module Monadic
  module Utils
    module Privacy
      # The word table of each chat, held here by the chat's id, never in the
      # session: a session is copied when a tab is saved for reconnecting,
      # and a copy of a table would split it in two. The session holds only
      # the chat id the table belongs to (MARK_KEY), which is what says that
      # the chat hides its words this way.
      #
      # A chat with the mark sends nothing when its table is not here (the
      # server was restarted, or the table was dropped to make room), and
      # nothing when it also holds the marked words or the masking of the
      # Privacy Filter: one chat hides its words one way.
      module Words
        MARK_KEY = :_word_table
        # Tables kept, the ones used longest ago dropped first. A chat whose
        # table was dropped sends nothing until it is started again.
        LIMIT = 500
        # What sending checks: the table and the snapshot a request was made
        # with, set while it is sent (fibers started in it inherit it).
        SENDING_KEY = :monadic_word_table_sending
        # Set on a copy of a chat's session that leaves the Privacy Filter's
        # state out (the copy HTTP requests are checked with), when the chat
        # had it beside its table.
        MIXED_KEY = :_word_table_mixed
        LEGACY_KEYS = [:_privacy_pipeline, :_privacy_session_enabled, MIXED_KEY].freeze

        TABLES = {}
        LOCK = Mutex.new

        module_function

        # The chat's table, or nil for a chat that does not hide its words
        # this way. Refused when the chat has the mark but no table, a mark of
        # another chat, or the Privacy Filter's state beside it.
        def table(session)
          return nil unless marked?(session)

          mark = session[MARK_KEY]

          chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
          unless mark.is_a?(String) && mark == chat_id
            raise Outbound::Refused, "the chat's word table is not this chat's; nothing was sent"
          end
          raise Outbound::Refused, 'the chat holds words hidden in two ways; nothing was sent' if legacy_state?(session)

          LOCK.synchronize do
            table = TABLES.delete(mark) or raise Outbound::Refused, "the chat's word table is not available; nothing was sent"
            TABLES[mark] = table
          end
        end

        # Whether the chat hides its words with a table: the session has the
        # mark's key (whatever its value; table refuses one that is not the
        # chat's id).
        def marked?(session)
          session.respond_to?(:key?) && (session.key?(MARK_KEY) || session.key?(MARK_KEY.to_s))
        end

        # The chat hides its words with a table from now on: the one the chat
        # has (also when this copy of its session was made before it was
        # started), or a new, empty one.
        def start!(session)
          existing = table(session)
          return existing if existing
          raise Outbound::Refused, 'the chat already marks words for the Privacy Filter' if legacy_state?(session)

          chat_id = Monadic::Workspace::Chats.current(session)
          table = LOCK.synchronize do
            found = TABLES.delete(chat_id) || WordTable.new
            TABLES[chat_id] = found
            TABLES.shift while TABLES.size > LIMIT
            found
          end
          session[MARK_KEY] = chat_id
          table
        end

        # The active words of the chat's table (none for a chat without one).
        def active_of(session)
          table = table(session)
          table ? table.active_words.map { |entry| entry[:word] } : []
        end

        # A request made with snapshot is sent in the block: every attempt
        # to send it (a retry included) is checked against the table first
        # (check_sending!). When the table changed after the snapshot was
        # taken, nothing is sent.
        # Without a table (nil), the block is only run (what an outer send
        # set stays).
        def sending(table, snapshot)
          return yield if table.nil?

          before = Fiber[SENDING_KEY]
          begin
            Fiber[SENDING_KEY] = [table, snapshot.revision].freeze
            yield
          ensure
            Fiber[SENDING_KEY] = before
          end
        end

        # The snapshot of the request each reply answers, held by the reply
        # object itself until the reply is put back, so that it is put back
        # with the words that request was sent with (a placeholder given
        # after it was sent is not one of them). While a reply is held, the
        # first snapshot noted for it is kept: in a round of tool calls, the
        # request that got the reply notes it before the rounds around it
        # return the same reply. At most REPLY_LIMIT are held, the oldest
        # dropped first (a reply never put back: an error, a reply not
        # shown); a reply noted again after it was dropped is held with the
        # later snapshot, which puts back no more than the words it knew.
        REPLY_LIMIT = 256
        REPLIES = {}.compare_by_identity

        def note_reply(replies, snapshot)
          return replies unless snapshot

          Array(replies).each do |reply|
            next unless reply.is_a?(Hash)

            LOCK.synchronize do
              REPLIES[reply] ||= snapshot
              REPLIES.shift while REPLIES.size > REPLY_LIMIT
            end
          end
          replies
        end

        # The reply's text with the chat's placeholders put back, as the
        # request it answers was sent; as it is when that is not known.
        def restore_reply(reply, text)
          snapshot = LOCK.synchronize { REPLIES.delete(reply) }
          snapshot ? snapshot.restore(text) : text
        end

        # A request to a model and the reading of its reply, run in the
        # block (a vendor's api_request, through Requests): once the
        # request's body is hidden, the snapshot it was hidden with
        # (sent_with). While the reply is read and the tools it calls are
        # run, tool_arguments puts back that snapshot's words, and the
        # replies the block returns are noted with it (note_reply). The
        # request of a round of tool calls is a request of its own.
        REQUEST_KEY = :monadic_word_table_request
        Request = Struct.new(:snapshot)

        def request
          before = Fiber[REQUEST_KEY]
          frame = Request.new
          begin
            Fiber[REQUEST_KEY] = frame
            replies = yield
          ensure
            Fiber[REQUEST_KEY] = before
          end
          note_reply(replies, frame.snapshot)
        end

        # The request being made was hidden with snapshot.
        def sent_with(snapshot)
          frame = Fiber[REQUEST_KEY]
          frame.snapshot = snapshot if frame
        end

        # Text a model wrote in reply to the request being made, kept as the
        # chat keeps replies: with the placeholders the request was sent
        # with put back (as it is outside a request, or before it is hidden).
        def put_back(text)
          snapshot = Fiber[REQUEST_KEY]&.snapshot
          snapshot ? snapshot.restore(text) : text
        end

        # Prepended to a vendor's helper: each api_request is a request.
        # It takes what every helper's api_request takes, and passes on the
        # keywords some add (Grok's disable_streaming:).
        module Requests
          def api_request(role, session, call_depth: 0, **options, &block)
            Words.request { super(role, session, call_depth: call_depth, **options, &block) }
          end
        end

        # The arguments of a tool a model called that are given to the tool
        # with the chat's words put back: places on this machine the tool
        # reads (a file or folder of the shared folder, a file shown on the
        # work screen). Every other argument stays as the model wrote it,
        # placeholders and all: what a tool writes, sends, searches for, runs
        # or draws.
        RESTORED_ARGUMENTS = {
          'read_file_from_shared_folder' => %w[filepath],
          'list_files_in_shared_folder' => %w[directory],
          'fetch_text_from_file' => %w[file],
          'fetch_text_from_pdf' => %w[file pdf],
          'fetch_text_from_office' => %w[file],
          'show_on_workbench' => %w[path]
        }.freeze

        # A tool call's arguments (keys as symbols or strings) as the tool is
        # given them: the RESTORED_ARGUMENTS of the tool with the exact
        # placeholders of the request whose reply called it put back.
        def tool_arguments(name, arguments)
          snapshot = Fiber[REQUEST_KEY]&.snapshot
          keys = RESTORED_ARGUMENTS[name.to_s]
          return arguments unless snapshot && keys && arguments.is_a?(Hash)

          arguments.to_h do |key, value|
            keys.include?(key.to_s) && value.is_a?(String) ? [key, snapshot.restore_exact(value)] : [key, value]
          end
        end

        # Called before each attempt to send to an outside host.
        def check_sending!
          table, revision = Fiber[SENDING_KEY]
          return unless table
          return if table.revision == revision

          raise Outbound::Refused, 'the words to hide changed while the request was being sent; nothing was sent'
        end

        # The Privacy Filter's state: its masking, its switch on, the words
        # marked for it, or the placeholders it gave.
        def legacy_state?(session)
          return true if LEGACY_KEYS.any? { |key| !session[key].nil? && session[key] != false }
          return true unless Outbound.legacy_terms(session).empty?

          state = session[:monadic_state]
          privacy = state.is_a?(Hash) ? (state[:privacy] || state['privacy']) : nil
          registry = privacy.is_a?(Hash) ? (privacy[:registry] || privacy['registry']) : nil
          registry.is_a?(Hash) && !registry.empty?
        end
      end
    end
  end
end
