# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'board'
require_relative 'look'
require_relative 'made'
require_relative 'shown'
require_relative 'whiteboard'
require_relative '../workspace/shared_folder_preview'
require_relative '../utils/extra_logger'

module Monadic
  module Workbench
    # The AI draws on a whiteboard of the work screen (draw_on_whiteboard):
    # on the one the asking tab shows, or on a new one. Shapes are added, or
    # changed by their id; ids given are removed. A line or an arrow may join
    # two shapes by their ids (from, to): its ends are kept at their middles
    # and drawn at their edges by the page.
    #
    # What a reply added is kept for its message (KEY): { "path", "ids" }
    # per whiteboard. Deleting the message, or a reply that ends without
    # one, takes those shapes off the whiteboard again (undo); what the user
    # drew stays, and so do the reply's changes to shapes it did not add.
    module Draw
      KEY = 'workbench_drawn'
      SHAPES_LIMIT = 200
      # Whiteboards a message keeps, and ids per whiteboard.
      LIMIT = 20
      IDS_LIMIT = Whiteboard::SHAPES_LIMIT
      CLOSED_LIMIT = 1000
      # The color of what the AI draws when it names none.
      COLOR = 'violet'
      NUMBERS = %w[x y w h x1 y1 x2 y2 size stroke].freeze

      class Refused < StandardError; end

      @open = {}
      @chats = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      # Draws shapes (a JSON array of shapes, or the array) and removes the
      # shapes of ids in remove, on the whiteboard caller's tab shows (a new
      # one when it shows none, or when new_board). Returns { item:, added:,
      # changed:, removed: }, or Refused (why).
      def run(caller, shapes: nil, remove: nil, new_board: false)
        raise Refused, 'this reply cannot draw on the work screen' unless caller

        list = parse(shapes)
        removing = Array(remove).map(&:to_s).reject(&:empty?)
        raise Refused, 'give shapes to draw or ids to remove' if list.empty? && removing.empty?
        raise Refused, "at most #{SHAPES_LIMIT} shapes in one call" if list.size > SHAPES_LIMIT

        app_name = caller.session&.dig(:parameters, 'app_name').to_s
        item = (shown_whiteboard(caller, app_name) unless new_board) || made_whiteboard(caller, app_name)
        path = item.dig('file', 'path')
        done = { added: [], changed: [], removed: [] }
        edited = Whiteboard.edit(caller.chat_id, path, app_name: app_name, origin: caller.origin,
                                                       epoch: caller.epoch) do |board_shapes|
          apply(board_shapes, list, removing, done)
        end
        item = edited || item
        add(caller.request_id, path, done[:added], chat_id: caller.chat_id)
        Shown.add(caller.request_id, item)
        done.merge(item: item)
      rescue Whiteboard::Refused => e
        raise Refused, e.message
      end

      # The shapes as given: an Array of Hashes (one Hash is one shape).
      def parse(shapes)
        return [] if shapes.nil? || (shapes.is_a?(String) && shapes.strip.empty?)

        value = shapes.is_a?(String) ? JSON.parse(shapes) : shapes
        value = [value] if value.is_a?(Hash)
        raise Refused, 'shapes must be a JSON array of shapes' unless value.is_a?(Array) && value.all?(Hash)

        value.map { |shape| shape.transform_keys(&:to_s) }
      rescue JSON::ParserError
        raise Refused, 'shapes is not valid JSON'
      end

      # Removes, then adds or changes, in place: shapes joined to others
      # last, so they can join shapes of the same call.
      def apply(board_shapes, list, removing, done)
        removing.each { |id| done[:removed] << id if board_shapes.reject! { |s| s['id'] == id } }
        joined, others = list.partition { |s| %w[line arrow].include?(s['type']) && (s['from'] || s['to']) }
        (others + joined).each do |input|
          id = input['id'].is_a?(String) && input['id'].match?(Whiteboard::ID) ? input['id'] : new_id(board_shapes)
          at = board_shapes.index { |s| s['id'] == id }
          if at
            board_shapes[at] = shape(board_shapes[at].merge(input).merge('id' => id), board_shapes)
            done[:changed] << id
          else
            board_shapes << shape({ 'color' => COLOR }.merge(input).merge('id' => id, 'by' => 'ai'), board_shapes)
            done[:added] << id
          end
        end
      rescue Whiteboard::Refused => e
        raise Refused, "a shape was not drawn: #{e.message}"
      end

      # A shape as the whiteboard keeps it: 'box' is a rectangle, numbers
      # written as text are numbers, and the ends of a line or an arrow
      # joining shapes are at their middles.
      def shape(input, board_shapes)
        out = input.dup
        out['type'] = 'rect' if out['type'] == 'box'
        NUMBERS.each { |key| out[key] = out[key].to_f if out[key].is_a?(String) && out[key].match?(/\A-?\d+(\.\d+)?\z/) }
        if %w[line arrow].include?(out['type'])
          [%w[from x1 y1], %w[to x2 y2]].each do |end_, x, y|
            next unless out[end_]

            other = board_shapes.find { |s| s['id'] == out[end_] && s['id'] != out['id'] }
            raise Refused, "#{end_} names no shape on the whiteboard (#{out[end_]})" unless other

            out[x], out[y] = middle(other)
          end
        end
        Whiteboard.shape_of(out)
      end

      def middle(shape)
        case shape['type']
        when 'line', 'arrow' then [(shape['x1'] + shape['x2']) / 2.0, (shape['y1'] + shape['y2']) / 2.0]
        when 'text' then [shape['x'], shape['y']]
        when 'pen', 'marker'
          xs = shape['points'].map(&:first)
          ys = shape['points'].map(&:last)
          [(xs.min + xs.max) / 2.0, (ys.min + ys.max) / 2.0]
        else [shape['x'] + shape['w'] / 2.0, shape['y'] + shape['h'] / 2.0]
        end
      end

      def new_id(board_shapes)
        loop do
          id = "ai-#{SecureRandom.alphanumeric(6)}"
          return id unless board_shapes.any? { |s| s['id'] == id }
        end
      end

      # The whiteboard of the chat the tab shows, or nil.
      def shown_whiteboard(caller, app_name)
        board = Board.existing(caller.chat_id) or return nil
        item = Look.target(board, caller).item
        path = item.dig('file', 'path').to_s
        return nil unless Monadic::Workspace::SharedFolderPreview.render_for(path) == 'whiteboard'

        folder, = Whiteboard.folder_of(caller.chat_id, app_name)
        Whiteboard.own?(folder, path) ? item : nil
      rescue Look::Refused
        nil
      end

      # A new whiteboard, made by the reply (deleting its message moves it
      # to the trash, as what a reply makes).
      def made_whiteboard(caller, app_name)
        item = Whiteboard.create(caller.chat_id, app_name: app_name, origin: caller.origin, epoch: caller.epoch)
        Made.add(caller.request_id, item.dig('file', 'path'), chat_id: caller.chat_id)
        item
      end

      # ---- what a reply drew, for its message ----------------------------

      # Records that the running reply request_id added ids to the
      # whiteboard at path.
      def add(request_id, path, ids, chat_id:)
        return if ids.empty? || !request_id

        @lock.synchronize do
          next if @closed.key?(request_id) || !Shown.running?(request_id)

          @chats[request_id] ||= chat_id
          list = (@open[request_id] ||= [])
          entry = list.find { |e| e['path'] == path }
          unless entry
            next if list.size >= LIMIT

            list << (entry = { 'path' => path, 'ids' => [] })
          end
          entry['ids'] = (entry['ids'] + ids).uniq.first(IDS_LIMIT)
        end
        nil
      end

      # The reply's records, once: its message takes them. Later adds for
      # it are dropped.
      def seal(request_id)
        @lock.synchronize do
          next [] if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @chats.delete(request_id)
          @open.delete(request_id) || []
        end
      end

      # The reply ended. What it drew and no message took (a reply stopped
      # before its message) is taken off again.
      def close(request_id, app_name: '')
        chat_id = @lock.synchronize { @chats[request_id] }
        drawn = clean(seal(request_id))
        undo(chat_id, drawn, app_name: app_name) if chat_id && drawn
      end

      # Takes the shapes of drawn (as a message keeps it) off its
      # whiteboards of the chat chat_id, those still on its work screen.
      # Returns the paths changed.
      def undo(chat_id, drawn, app_name:)
        # Not a tab's doing: the board takes it without one.
        origin = { actor: 'system', source: 'undo' }
        epoch = Monadic::Workspace::Chats.epoch(chat_id)
        Array(clean(drawn)).filter_map do |entry|
          ids = entry['ids']
          changed = Whiteboard.edit(chat_id, entry['path'], app_name: app_name, origin: origin, epoch: epoch) do |shapes|
            shapes.reject! { |s| ids.include?(s['id']) }
          end
          entry['path'] if changed
        rescue Whiteboard::Refused => e
          Monadic::Utils::ExtraLogger.log { "[Workbench] drawn shapes not taken off: #{e.message}" }
          nil
        end
      end

      # What a message keeps (from a reply, or from history or an imported
      # file): whiteboards of the chat folders, with the ids added; nil when
      # none is left.
      def clean(drawn)
        return nil unless drawn.is_a?(Array)

        kept = drawn.first(LIMIT).filter_map do |entry|
          next unless entry.is_a?(Hash)

          path = entry['path'] || entry[:path]
          ids = Array(entry['ids'] || entry[:ids]).select { |id| id.is_a?(String) && id.match?(Whiteboard::ID) }.uniq
          next unless Made.clean([path]) && path.end_with?(Whiteboard::EXTENSION) && !ids.empty?

          { 'path' => path, 'ids' => ids.first(IDS_LIMIT) }
        end
        kept = kept.uniq { |entry| entry['path'] }
        kept.empty? ? nil : kept
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @open.clear
          @chats.clear
          @closed.clear
        end
      end
    end
  end
end
