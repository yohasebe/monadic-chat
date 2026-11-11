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

        # The chat's table as it is kept in the chat's saved conversation or
        # in a file (WordTable#to_h), or nil when no table is held for it.
        def saved(chat_id)
          LOCK.synchronize { TABLES[chat_id] }&.to_h
        end

        # The chat in session is one taken back (from the history, from a
        # file) that hides its words with a table: the table held for it, or
        # else the one given (saved). The chat has the mark from here on
        # whether or not what was given can be read: a chat whose table
        # cannot be read sends nothing. Nothing is done for a chat with
        # neither (nil given): it never had a table.
        def restore!(session, saved)
          chat_id = Monadic::Workspace::Chats.current(session)
          held = LOCK.synchronize { TABLES.key?(chat_id) }
          return if saved.nil? && !held

          table = held ? nil : readable(saved)
          LOCK.synchronize do
            if table && !TABLES.key?(chat_id)
              TABLES[chat_id] = table
              TABLES.shift while TABLES.size > LIMIT
            end
          end
          session[MARK_KEY] = chat_id
        end

        def readable(saved)
          WordTable.from_h(saved)
        rescue WordTable::Invalid
          nil
        end

        # The table of a file being imported, as restore! takes it, or nil
        # when the file has none. registry (placeholder => word) and terms
        # ([{ text:, type: }]) are what files of earlier versions hold
        # instead. Invalid when it cannot be read, or when the file holds both.
        def file_table(file, registry: {}, terms: [])
          raise WordTable::Invalid, 'the words of the file are not readable' unless registry.is_a?(Hash)

          older = !registry.empty? || !terms.empty?
          return older ? older_file_table(registry, terms) : nil unless file.is_a?(Hash) && file.key?('word_table')
          raise WordTable::Invalid, 'the file holds words hidden in two ways' if older

          WordTable.from_h(file['word_table'])
          file['word_table']
        end

        # The words of an earlier version's file as a table. Each placeholder
        # stays as it was, so that what the file says with it still reads back.
        def older_file_table(registry, terms)
          mapping = {}
          active = []
          high = Hash.new(0)
          registry.each do |placeholder, word|
            id = placeholder.to_s[/\A<<(.+)>>\z/, 1].to_s
            match = WordTable::ID_RE.match(id) or raise WordTable::Invalid, 'a placeholder of another form'
            mapping[id] = { 'word' => word, 'type' => match[1] }
            active << { 'word' => word, 'id' => id, 'type' => match[1] }
            high[match[1]] = [high[match[1]], match[2].to_i].max
          end
          table = WordTable.from_h('schema' => WordTable::SCHEMA, 'mapping' => mapping, 'active' => active,
                                   'high' => high.to_h, 'kept' => [], 'revision' => 0)
          table.confirm_all!(terms.map { |term| [term[:text], term[:type]] })
          table.to_h
        end

        # What a file shared without its table says for each active word:
        # placeholder => word, as a Privacy Filter registry is.
        def masking(table)
          table.active_words.to_h { |entry| [WordTable.placeholder(entry[:id]), entry[:word]] }
        end

        # What the page shows of the chat's table.
        def shown(session)
          return { 'marked' => false, 'active' => [], 'kept' => [] } unless marked?(session)

          begin
            found = table(session)
          rescue Outbound::Refused
            return { 'marked' => true, 'unavailable' => true, 'active' => [], 'kept' => [] }
          end
          { 'marked' => true,
            'active' => found.active_words.map { |entry| { 'word' => entry[:word], 'type' => entry[:type] } },
            'kept' => found.kept_words }
        end

        # The words a finder gave for a text ([{ original:, type: }, ...]) that
        # the user has not decided about (table: nil for a chat without one),
        # each once, the first type found. Those no table could take are left
        # out.
        def candidates(table, entities)
          entities.each_with_object({}) do |entity, found|
            word = entity['original'] || entity[:original]
            type = entity['type'] || entity[:type]
            next if found.key?(word) || !WordTable.word?(word) || !WordTable.type?(type)
            next if table&.standing(word)

            found[word] = { 'word' => word, 'type' => type }
          end.values
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

          replies_in(replies).each do |reply|
            next unless reply.is_a?(Hash)

            LOCK.synchronize do
              next if AS_IS.key?(reply)

              REPLIES[reply] ||= snapshot
              REPLIES.shift while REPLIES.size > REPLY_LIMIT
            end
          end
          replies
        end

        # Replies whose text is not the model's to put back: made from what
        # tools gave (data, in which a placeholder is only text), or put
        # together from parts each put back with the snapshot of the request
        # it came from. Shown as they are for as long as the reply lives
        # (the reply is held weakly, by itself, apart from the snapshots
        # REPLY_LIMIT drops): no snapshot is noted for it after. Nothing is
        # marked outside a request that was hidden.
        AS_IS = ObjectSpace::WeakMap.new

        def as_is(replies)
          return replies unless Fiber[REQUEST_KEY]&.snapshot

          replies_in(replies).each do |reply|
            next unless reply.is_a?(Hash)

            LOCK.synchronize do
              AS_IS[reply] = true
              REPLIES.delete(reply)
            end
          end
          replies
        end

        # The replies an api_request returns (a reply, or an Array of them):
        # Array() would take a Hash for its pairs.
        def replies_in(replies)
          replies.is_a?(Array) ? replies : [replies]
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

        # Texts sent outside a chat request (a second opinion, the context
        # of a chat), hidden as text with one snapshot of the table, made
        # again once if the table changed meanwhile: [snapshot, texts].
        def hide_texts(table, texts)
          2.times do
            snapshot = table.snapshot
            budget = WordTable::Budget.new
            hidden = texts.map { |text| snapshot.raw(text.to_s, budget) }
            return [snapshot, hidden] if table.revision == snapshot.revision
          end
          raise Outbound::Refused, 'the words to hide kept changing; nothing was sent'
        end

        # Text as it is read out by a speech service: each hidden word read as
        # its placeholder's type and number, whether the text holds the
        # placeholder (as a model wrote it) or the word (a reply put back).
        def spoken(table, text)
          label = ->(_) { Outbound.spoken_label(Regexp.last_match(1), Regexp.last_match(2)) }
          read = text.to_s.gsub(WordTable::RESTORE_RE, &label)
          table.snapshot.raw(read).gsub(WordTable::RESTORE_RE, &label)
        end

        # What came back for texts hidden with snapshot (hide_texts), with the
        # placeholders put back in every string it holds (keys stay as they
        # are).
        def restore_all(snapshot, value)
          case value
          when String then snapshot.restore(value)
          when Array then value.map { |item| restore_all(snapshot, item) }
          when Hash then value.transform_values { |item| restore_all(snapshot, item) }
          else value
          end
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
        # with the chat's words put back: what the tool reads on this machine
        # (a file or folder of the shared folder, a file shown on the work
        # screen, the Knowledge Base it searches, whose passages keep the
        # words as saved). Every other argument stays as the model wrote it,
        # placeholders and all: what a tool writes, sends, searches for
        # elsewhere, runs or draws.
        RESTORED_ARGUMENTS = {
          'read_file_from_shared_folder' => %w[filepath],
          'list_files_in_shared_folder' => %w[directory],
          'fetch_text_from_file' => %w[file],
          'fetch_text_from_pdf' => %w[file pdf],
          'fetch_text_from_office' => %w[file],
          'show_on_workbench' => %w[path],
          'library_search' => %w[query]
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
