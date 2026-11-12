# frozen_string_literal: true

require_relative '../workspace/shared_folder_preview'

module Monadic
  module Workbench
    # What a reply showed on the work screen (put_on_workbench,
    # show_on_workbench), for its message: one record per file version,
    # kept in memory while the reply runs, given to its message once
    # (seal) and dropped when the reply ends without one (close). A reply
    # that ended takes nothing more: what a late tool shows is not carried
    # to the next reply.
    module Shown
      LIMIT = 20
      # Replies ended, oldest first: a late add for one of them is dropped.
      CLOSED_LIMIT = 1000
      KEYS = %w[path name sha256 preview render section].freeze
      # A section of a document the record opens the file at (Document).
      SECTION = /\A[a-z0-9-]{1,40}\z/
      PATH_LIMIT = 1024
      NAME_LIMIT = 255

      @open = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      # What a file item is recorded as.
      def event(item)
        file = item['file'] || {}
        { 'path' => file['path'], 'name' => file['name'], 'sha256' => file['sha256'], 'preview' => file['preview'],
          'render' => Monadic::Workspace::SharedFolderPreview.render_for(file['path']) }
      end

      # Records that the reply request_id showed item, while the reply runs
      # (section: the section of a document it opens at). Whether the reply
      # runs is asked under the same lock as seal takes, so a reply that
      # ended cannot be given a new place.
      def add(request_id, item, section: nil)
        record = clean([event(item).merge('section' => section)])&.first or return
        @lock.synchronize do
          next if @closed.key?(request_id) || !running?(request_id)

          list = (@open[request_id] ||= [])
          next if list.any? do |e|
            e['path'] == record['path'] && (e['sha256'] == record['sha256'] || (record['section'] && e['section'] == record['section']))
          end

          list << record if list.size < LIMIT
        end
      end

      # The reply's records, once: its message takes them. Later adds for
      # it are dropped.
      def seal(request_id)
        @lock.synchronize do
          next [] if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @open.delete(request_id) || []
        end
      end

      # The reply ended (with or without a message): nothing is kept.
      def close(request_id)
        seal(request_id)
        nil
      end

      # Records as a message keeps them (from a reply, or from history or
      # an imported file): the known keys only, of the right form, at most
      # LIMIT; nil when none is left. A record names a file; it gives no
      # right to read it.
      def clean(records)
        return nil unless records.is_a?(Array)

        kept = records.first(LIMIT).filter_map do |record|
          next unless record.is_a?(Hash)

          out = record.transform_keys(&:to_s).slice(*KEYS)
          next unless path?(out['path']) && out['sha256'].is_a?(String) && out['sha256'].match?(/\A\h{64}\z/)
          next unless out['name'].is_a?(String) && !out['name'].empty? && out['name'].length <= NAME_LIMIT
          next unless Monadic::Workspace::SharedFolderPreview.kind_for(out['path']) == out['preview']

          out['render'] = Monadic::Workspace::SharedFolderPreview.render_for(out['path'])
          out.delete('section') unless out['section'].is_a?(String) && out['section'].match?(SECTION)
          out.compact
        end
        kept.empty? ? nil : kept
      end

      def path?(path)
        path.is_a?(String) && path.valid_encoding? && !path.empty? && path.length <= PATH_LIMIT &&
          !path.start_with?('/') && !path.include?("\0") && !path.include?('\\') &&
          path.split('/').none? { |part| part.empty? || part == '.' || part == '..' }
      end

      # The reply is running and was not stopped (WebSocketHelper::Replies,
      # loaded with the server's socket).
      def running?(request_id)
        return false unless defined?(WebSocketHelper::Replies)

        handle = WebSocketHelper::Replies.find(request_id)
        handle && !handle.cancelled? && %i[running answered].include?(handle.phase)
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @open.clear
          @closed.clear
        end
      end
    end
  end
end
