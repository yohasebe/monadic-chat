# frozen_string_literal: true

require 'json'
require_relative 'board'
require_relative 'channel'
require_relative '../workspace/folders'
require_relative '../workspace/chats'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # A whiteboard on the work screen: a file of the chat's folder,
    # whiteboards/whiteboard-<n>.wb.json, holding the shapes drawn on it
    # (on a board of WIDTH × HEIGHT). The user's page draws on it and sends
    # the whole board when it changes (save); it is taken only as clean
    # makes it (known shapes, colors and sizes, numbers in range, within
    # the limits), written in place of the file, and the work screen's item
    # takes the new version.
    module Whiteboard
      DIRNAME = 'whiteboards'
      EXTENSION = '.wb.json'
      NAME = /\Awhiteboard-([1-9]\d{0,3})\z/
      WIDTH = 1600
      HEIGHT = 1000
      # How far outside the board a point may be.
      MARGIN = 400
      TYPES = %w[pen marker line arrow rect ellipse text].freeze
      COLORS = %w[black red orange yellow lime green sky blue violet pink
                  white silver gray brown peach olive teal navy purple magenta].freeze
      # A width or size is taken as the nearest of these.
      STROKES = [3, 6, 12, 24].freeze
      SIZES = [20, 32, 48, 72].freeze
      # How a pen stroke, a rectangle or an ellipse is filled (true: light).
      FILLS = %w[none light solid].freeze
      BY = %w[user ai].freeze
      ID = /\A[A-Za-z0-9_-]{1,32}\z/
      SHAPES_LIMIT = 2000
      PEN_POINTS = 5000
      POINTS_LIMIT = 100_000
      TEXT_CHARS = 1000
      BYTES_LIMIT = 2 * 1024 * 1024

      class Refused < StandardError; end

      module_function

      # The board as it is kept: { version, width, height, shapes }, each
      # shape with the keys of its type only. Refused (why) otherwise.
      def clean(data)
        raise Refused, 'not a whiteboard' unless data.is_a?(Hash) && data['shapes'].is_a?(Array)

        shapes = data['shapes']
        raise Refused, 'too many shapes' if shapes.size > SHAPES_LIMIT

        points = 0
        ids = {}
        kept = shapes.map do |shape|
          out = shape_of(shape)
          raise Refused, 'a shape is named twice' if ids.key?(out['id'])

          ids[out['id']] = true
          points += out['points'].size if out['points']
          raise Refused, 'too many points' if points > POINTS_LIMIT

          out
        end
        { 'version' => 1, 'width' => WIDTH, 'height' => HEIGHT, 'shapes' => kept }
      end

      def shape_of(shape)
        raise Refused, 'a shape is not one' unless shape.is_a?(Hash)

        type = shape['type']
        raise Refused, 'a shape of an unknown type' unless TYPES.include?(type)
        raise Refused, 'a shape without a name' unless shape['id'].is_a?(String) && shape['id'].match?(ID)

        out = { 'id' => shape['id'], 'type' => type, 'by' => BY.include?(shape['by']) ? shape['by'] : 'user',
                'color' => COLORS.include?(shape['color']) ? shape['color'] : 'black' }
        case type
        when 'pen', 'marker'
          list = shape['points']
          raise Refused, 'a pen stroke needs points' unless list.is_a?(Array) && list.size.between?(1, PEN_POINTS)

          out['points'] = list.map { |p| point(p) }
          out['stroke'] = stroke(shape)
          out['fill'] = fill(shape) if type == 'pen'
        when 'line', 'arrow'
          out.merge!('x1' => x(shape['x1']), 'y1' => y(shape['y1']), 'x2' => x(shape['x2']), 'y2' => y(shape['y2']))
          out['stroke'] = stroke(shape)
        when 'rect', 'ellipse'
          out.merge!('x' => x(shape['x']), 'y' => y(shape['y']), 'w' => size(shape['w'], WIDTH), 'h' => size(shape['h'], HEIGHT))
          out['stroke'] = stroke(shape)
          out['fill'] = fill(shape)
        when 'text'
          text = shape['text']
          raise Refused, 'a text needs some text' unless text.is_a?(String) && text.valid_encoding? && !text.strip.empty?
          raise Refused, 'a text is too long' if text.length > TEXT_CHARS

          out.merge!('x' => x(shape['x']), 'y' => y(shape['y']), 'text' => text.gsub(/[^\P{Cc}\n]/, ''),
                     'size' => nearest(shape['size'], SIZES, SIZES[0]))
        end
        out
      end

      def point(value)
        raise Refused, 'a point is not two numbers' unless value.is_a?(Array) && value.size == 2

        [x(value[0]), y(value[1])]
      end

      def x(value) = number(value, -MARGIN, WIDTH + MARGIN)
      def y(value) = number(value, -MARGIN, HEIGHT + MARGIN)

      def size(value, limit) = number(value, 0, limit + MARGIN)

      def number(value, low, high)
        raise Refused, 'a number is out of range' unless value.is_a?(Numeric) && value.to_f.finite? && value.between?(low, high)

        value.to_f.round(1)
      end

      def stroke(shape) = nearest(shape['stroke'], STROKES, STROKES[1])

      def fill(shape)
        value = shape['fill']
        return 'light' if value == true

        FILLS.include?(value) ? value : 'none'
      end

      # The one of choices nearest to value (a finite number), else fallback.
      def nearest(value, choices, fallback)
        return fallback unless value.is_a?(Numeric) && value.to_f.finite?

        choices.min_by { |c| (c - value).abs }
      end

      # A new, empty whiteboard in the chat's folder (the next free number),
      # put on the work screen for the tab. Returns the board's item.
      def create(chat_id, app_name:, origin:, epoch:)
        folder, dir = folder_of(chat_id, app_name)
        taken = Dir.children(dir).filter_map { |f| f.delete_suffix(EXTENSION)[NAME, 1]&.to_i if f.end_with?(EXTENSION) }
        name = "whiteboard-#{(taken.max || 0) + 1}"
        write(dir, name, clean({ 'shapes' => [] }))
        item, = Board.for(chat_id).add_file(path: File.join(folder, DIRNAME, "#{name}#{EXTENSION}"), origin: origin,
                                            epoch: epoch, wait: 0)
        Channel.changed(chat_id)
        item
      end

      # The board item_id (a whiteboard of the chat, at version: what the
      # page drew on) as data now has it. Refused when the item is not a
      # whiteboard of this chat or changed since (another tab saved it).
      # Returns the item at its new version.
      def save(chat_id, item_id:, version:, data:, app_name:, origin:, epoch:)
        board = Board.existing(chat_id) or raise Refused, 'no work screen'
        path = board.file_entry(item_id.to_s, sha256: version.to_s)['path'].to_s
        folder, dir = folder_of(chat_id, app_name)
        name = File.basename(path).delete_suffix(EXTENSION)
        unless path == File.join(folder, DIRNAME, "#{name}#{EXTENSION}") && name.match?(NAME)
          raise Refused, 'not a whiteboard of this chat'
        end

        write(dir, name, clean(data))
        item, = board.add_file(path: path, origin: origin, epoch: epoch, wait: 0)
        Channel.changed(chat_id)
        item
      rescue Artifact::Changed
        raise Refused, 'changed'
      rescue Artifact::NotAllowed
        raise Refused, 'not a whiteboard of this chat'
      end

      # The chat's folder (relative to the shared folder) and its
      # whiteboards folder (a real path, made when missing).
      def folder_of(chat_id, app_name)
        folder = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: app_name)[:relative_dir]
        root = File.realpath(Monadic::Utils::Environment.data_path)
        dir = File.join(root, folder, DIRNAME)
        Monadic::Utils::SharedPathGuard.mkdir_p!(dir, strict: true)
        [folder, dir]
      end

      def write(dir, name, board_data)
        json = JSON.generate(board_data)
        raise Refused, 'the whiteboard is too large' if json.bytesize > BYTES_LIMIT

        Monadic::Utils::SharedPathGuard.write_file!(File.join(dir, "#{name}#{EXTENSION}"), json, mode: 'w', replace: true,
                                                                                                  strict: true)
      end
    end
  end
end
