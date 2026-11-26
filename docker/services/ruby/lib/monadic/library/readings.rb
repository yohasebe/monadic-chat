# frozen_string_literal: true

require 'securerandom'
require 'time'

module Monadic
  module Library
    # What a reply read from the Library: one record per search, with the
    # excerpts its model was given, each with an id of its own. Kept in
    # memory while the reply runs and given to its message once (seal), or
    # to the user's message of the request when the reply ends without one
    # (take). A reply cites an excerpt by its link (LINK); seal marks the
    # excerpts the reply's text links to.
    #
    # A search is recorded before its excerpts go to the model (add): a
    # search that cannot be recorded gives the model nothing.
    module Readings
      KEY = 'library_readings'
      LIMIT = 20
      EXCERPTS_LIMIT = 10
      QUERY_CHARS = 200
      TEXT_CHARS = 600
      READING_ID = /\Ar_\h{16}\z/
      EXCERPT_ID = /\Ax_\h{16}\z/
      LINK_PREFIX = 'mc:read:'
      CLOSED_LIMIT = 1000

      @open = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      def reading_id
        "r_#{SecureRandom.hex(8)}"
      end

      def excerpt_id
        "x_#{SecureRandom.hex(8)}"
      end

      # The link a reply cites an excerpt by.
      def link(excerpt_id)
        "#{LINK_PREFIX}#{excerpt_id}"
      end

      # Records a search of the reply request_id. reading: { 'id', 'query',
      # 'excerpts' => [{ 'id', 'conversation_id', 'title', 'source',
      # 'turn', 'text' }] } (path, when its copy is on the work screen, can
      # be given later with placed). False when the reply ended or holds
      # LIMIT searches: the search is not to be given to the model then.
      def add(request_id, chat_id, reading, session: nil)
        record = clean([reading.merge('at' => Time.now.utc.iso8601)])&.first or return false
        @lock.synchronize do
          next false if request_id.nil? || @closed.key?(request_id)

          entry = (@open[request_id] ||= { chat_id: chat_id, session: session, records: [] })
          next false if entry[:records].size >= LIMIT

          entry[:records] << record
          true
        end
      end

      # The path in the chat's folder of the copy a search put on the work
      # screen.
      def placed(request_id, reading_id, path)
        @lock.synchronize do
          record = @open[request_id]&.fetch(:records)&.find { |r| r['id'] == reading_id }
          record['path'] = path.to_s if record && path
        end
      end

      # The reply's records, once, with the excerpts its text links to
      # marked as cited: its message takes them.
      def seal(request_id, text: nil)
        entry = take(request_id) or return []
        cite(entry[:records], text)
      end

      # The reply's records with its chat and session ({ chat_id:, session:,
      # records: }), once, or nil.
      def take(request_id)
        @lock.synchronize do
          next nil if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @open.delete(request_id)
        end
      end

      # The records with 'cited' set to the excerpts text links to.
      def cite(records, text)
        linked = text.to_s.scan(/#{Regexp.escape(LINK_PREFIX)}(x_\h{16})/o).flatten.uniq
        records.map do |record|
          ids = Array(record['excerpts']).map { |e| e['id'] } & linked
          ids.empty? ? record : record.merge('cited' => ids)
        end
      end

      # Records as a message keeps them (from a reply, from history or an
      # imported file): the known keys of the right form, at most LIMIT;
      # nil when none is left.
      def clean(records)
        return nil unless records.is_a?(Array)

        kept = records.first(LIMIT).filter_map { |record| clean_record(record) }
        kept.empty? ? nil : kept
      end

      def clean_record(record)
        return nil unless record.is_a?(Hash)

        out = record.transform_keys(&:to_s).slice('id', 'query', 'at', 'path', 'excerpts', 'cited')
        return nil unless out['id'].is_a?(String) && out['id'].match?(READING_ID)

        out['query'] = out['query'].to_s[0, QUERY_CHARS]
        out.delete('at') unless out['at'].is_a?(String)
        out.delete('path') unless out['path'].is_a?(String) && !out['path'].empty?
        out['excerpts'] = Array(out['excerpts']).first(EXCERPTS_LIMIT).filter_map { |e| clean_excerpt(e) }
        ids = out['excerpts'].map { |e| e['id'] }
        cited = Array(out['cited']).select { |id| ids.include?(id) }
        cited.empty? ? out.delete('cited') : out['cited'] = cited
        out
      end

      def clean_excerpt(excerpt)
        return nil unless excerpt.is_a?(Hash)

        out = excerpt.transform_keys(&:to_s).slice('id', 'conversation_id', 'title', 'source', 'turn', 'text')
        return nil unless out['id'].is_a?(String) && out['id'].match?(EXCERPT_ID)

        %w[conversation_id title source].each { |k| out[k] = out[k].to_s[0, QUERY_CHARS] }
        out['turn'] = out['turn'].is_a?(Integer) ? out['turn'] : nil
        out['text'] = out['text'].to_s[0, TEXT_CHARS]
        out.compact
      end
    end
  end
end
