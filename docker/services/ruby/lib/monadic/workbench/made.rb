# frozen_string_literal: true

require_relative 'shown'
require_relative '../workspace/folders'
require_relative 'turn_trash'
require_relative 'revision'
require_relative 'board'
require_relative 'channel'

module Monadic
  module Workbench
    # What a reply made in its chat's folder (a run folder of
    # Workbench::ChatOutput, a file of Workbench::Put), for its message: one
    # path per thing made, kept in memory while the reply runs, given to
    # its message once (seal). Deleting the message moves what it made to
    # the chat's trash (Workbench::TurnTrash), and so does a reply that ends
    # without a message (close); nothing else in the shared folder is
    # touched.
    #
    # What a reply changed in place that an earlier turn made is kept as a
    # revision (Workbench::Revision): { "path", "before" }, given to its
    # message as REVISIONS_KEY, so deleting the message (or stopping the
    # reply) puts it back as it was.
    module Made
      LIMIT = 100
      REVISIONS_KEY = 'workbench_revisions'
      # Replies ended, oldest first: a late add for one of them is dropped.
      CLOSED_LIMIT = 1000

      @open = {}
      @revised = {}
      @chats = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      # Records that the reply request_id made path (relative to the shared
      # folder) for the chat chat_id, while the reply runs.
      def add(request_id, path, chat_id: nil)
        return unless request_id && Shown.path?(path)

        @lock.synchronize do
          next if @closed.key?(request_id) || !Shown.running?(request_id)

          @chats[request_id] ||= chat_id if chat_id
          list = (@open[request_id] ||= [])
          list << path if list.size < LIMIT && !list.include?(path)
        end
        nil
      end

      # Records that the running reply request_id changes path in place,
      # kept as it was at before (both relative to the shared folder).
      def revise(request_id, path, before, chat_id: nil)
        return nil unless request_id && Shown.path?(path) && Shown.path?(before)

        @lock.synchronize do
          next nil if @closed.key?(request_id) || !Shown.running?(request_id)

          @chats[request_id] ||= chat_id if chat_id
          list = (@revised[request_id] ||= [])
          next nil if list.size >= LIMIT || list.any? { |rev| rev['path'] == path }

          list << { 'path' => path, 'before' => before }
          list.last.dup
        end
      end

      # Whether the reply request_id made path or already kept it as a
      # revision: nothing more is kept for it then.
      def handled?(request_id, path)
        @lock.synchronize do
          (@open[request_id] || []).include?(path) || (@revised[request_id] || []).any? { |rev| rev['path'] == path }
        end
      end

      # The reply's revisions, once: its message takes them.
      def seal_revisions(request_id)
        @lock.synchronize { @revised.delete(request_id) || [] }
      end

      # What the running reply request_id made so far (its message takes
      # it later).
      def pending(request_id)
        @lock.synchronize { (@open[request_id] || []).dup }
      end

      # The reply's paths, once: its message takes them. Later adds for it
      # are dropped.
      def seal(request_id)
        @lock.synchronize do
          next [] if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @chats.delete(request_id)
          @open.delete(request_id) || []
        end
      end

      # The reply ended. What it made and no message took (a reply stopped
      # before its message) goes to its chat's trash. Returns the paths
      # moved.
      def close(request_id)
        chat_id = @lock.synchronize { @chats[request_id] }
        left = clean(seal(request_id))
        revisions = clean_revisions(seal_revisions(request_id))
        return [] unless left || revisions

        folder = (left || revisions.map { |rev| rev['path'] }).first.split('/').first(2).join('/')
        label = TurnTrash.label("stopped-#{request_id}")
        moved = TurnTrash.move(folder, Array(left).select { |path| path.start_with?("#{folder}/") }, label)
        put_back = revisions ? Revision.undo(folder, revisions, label) : []
        board = chat_id && !(moved + put_back).empty? && Board.existing(chat_id)
        Channel.changed(chat_id) if board && (!board.drop_files(moved).empty? || !put_back.empty?)
        moved + put_back
      rescue StandardError => e
        warn "[Made] what a stopped reply made was not moved to the trash: #{e.class}"
        []
      end

      # Paths as a message keeps them (from a reply, or from history or an
      # imported file): relative paths of the chat folders only, at most
      # LIMIT; nil when none is left. A path names what was made; it gives
      # no right to read it, and the trash moves only what is inside the
      # chat's own folder.
      def clean(paths)
        return nil unless paths.is_a?(Array)

        prefix = "#{Monadic::Workspace::Folders::ROOT_DIRNAME}/"
        kept = paths.first(LIMIT).select { |path| Shown.path?(path) && path.start_with?(prefix) }.uniq
        kept.empty? ? nil : kept
      end

      # Revisions as a message keeps them: { "path", "before" } pairs of
      # the same chat folder, before in its revisions folder; nil when none
      # is left.
      def clean_revisions(revisions)
        return nil unless revisions.is_a?(Array)

        kept = revisions.first(LIMIT).filter_map do |rev|
          next unless rev.is_a?(Hash)

          path = rev['path'] || rev[:path]
          before = rev['before'] || rev[:before]
          next unless clean([path]) && clean([before])

          folder = path.split('/').first(2)
          parts = before.split('/')
          next unless parts.first(2) == folder && parts[2] == Revision::DIRNAME && parts.size > 4

          { 'path' => path, 'before' => before }
        end
        kept = kept.uniq { |rev| rev['path'] }
        kept.empty? ? nil : kept
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @revised.clear
          @open.clear
          @chats.clear
          @closed.clear
        end
      end
    end
  end
end
