# frozen_string_literal: true

require 'json'
require_relative 'board'
require_relative 'channel'
require_relative 'whiteboard_background'
require_relative '../workspace/folders'
require_relative '../workspace/chats'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # A whiteboard on the work screen: a file of the chat's folder,
    # whiteboards/whiteboard-<n>.wb.json, holding the shapes drawn on it
    # (on a sheet, its Frame). Version 1 is a plain sheet of WIDTH ×
    # HEIGHT; version 2 is drawn on a picture (WhiteboardBackground's
    # record), the sheet taking its proportions. The user's page draws on it and sends
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
      # The sheet shapes are placed on (its width and height): PLAIN, or one
      # made from the picture under the board, its longer side LONG_SIDE.
      Frame = Data.define(:width, :height)
      PLAIN = Frame.new(width: WIDTH, height: HEIGHT)
      LONG_SIDE = 1600
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
      ROUTES = %w[straight elbow].freeze
      BY = %w[user ai].freeze
      ID = /\A[A-Za-z0-9_-]{1,32}\z/
      SHAPES_LIMIT = 2000
      PEN_POINTS = 5000
      POINTS_LIMIT = 100_000
      TEXT_CHARS = 1000
      BYTES_LIMIT = 2 * 1024 * 1024

      class Refused < StandardError; end

      # One write of a chat's whiteboards at a time (a save from a page, a
      # change by the AI): each reads, checks and writes it whole. Chats do
      # not wait for each other.
      LOCKS = {}
      LOCKS_GUARD = Mutex.new

      module_function

      # The board as it is kept: { version, width, height, background,
      # shapes }, each shape with the keys of its type only, on the sheet of
      # background (the picture under it, WhiteboardBackground's record, or
      # nil for a plain one). Refused (why) otherwise.
      def clean(data, background: nil)
        raise Refused, 'not a whiteboard' unless data.is_a?(Hash) && data['shapes'].is_a?(Array)

        shapes = data['shapes']
        raise Refused, 'too many shapes' if shapes.size > SHAPES_LIMIT

        frame = frame_of(background)
        points = 0
        ids = {}
        kept = shapes.map do |shape|
          out = shape_of(shape, frame)
          raise Refused, 'a shape is named twice' if ids.key?(out['id'])

          ids[out['id']] = true
          points += out['points'].size if out['points']
          raise Refused, 'too many points' if points > POINTS_LIMIT

          out
        end
        board = { 'version' => background ? 2 : 1, 'width' => frame.width, 'height' => frame.height }
        board['background'] = background if background
        board.merge('shapes' => kept)
      end

      # The picture under a kept board (data: its JSON, parsed), or nil for
      # a plain one. Refused for a kind this version does not know.
      def background_of(data)
        raise Refused, 'not a whiteboard' unless data.is_a?(Hash)

        case data['version']
        when 1 then nil
        when 2 then WhiteboardBackground.clean(data['background']) or raise Refused, 'the picture under it is not named'
        else raise Refused, 'a whiteboard of a kind this version does not know'
        end
      end

      # The sheet of a board with background under it (nil: PLAIN). It is
      # made from the picture's record, never read from the file.
      def frame_of(background)
        return PLAIN unless background

        width, height = WhiteboardBackground.size_for(background, LONG_SIDE)
        Frame.new(width: width, height: height)
      end

      def shape_of(shape, frame = PLAIN)
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

          out['points'] = list.map { |p| point(p, frame) }
          out['stroke'] = stroke(shape)
          out['fill'] = fill(shape) if type == 'pen'
        when 'line', 'arrow'
          out.merge!('x1' => x(shape['x1'], frame), 'y1' => y(shape['y1'], frame), 'x2' => x(shape['x2'], frame),
                     'y2' => y(shape['y2'], frame))
          out['stroke'] = stroke(shape)
          # The shapes it joins (its ends drawn at their edges), by id.
          %w[from to].each { |end_| out[end_] = shape[end_] if shape[end_].is_a?(String) && shape[end_].match?(ID) }
          # Drawn with right angles ('elbow') or straight (the default).
          out['route'] = shape['route'] if ROUTES.include?(shape['route'])
          # A text written by it (near its middle), when there is one.
          unless shape['text'].nil? || shape['text'].to_s.strip.empty?
            out['text'] = text_of(shape['text'])
            out['size'] = nearest(shape['size'], SIZES, SIZES[0])
          end
        when 'rect', 'ellipse'
          out.merge!('x' => x(shape['x'], frame), 'y' => y(shape['y'], frame), 'w' => size(shape['w'], frame.width),
                     'h' => size(shape['h'], frame.height))
          out['stroke'] = stroke(shape)
          out['fill'] = fill(shape)
          # A text written in it (its middle), when there is one.
          unless shape['text'].nil? || shape['text'].to_s.strip.empty?
            out['text'] = text_of(shape['text'])
            out['size'] = nearest(shape['size'], SIZES, SIZES[0])
          end
        when 'text'
          out.merge!('x' => x(shape['x'], frame), 'y' => y(shape['y'], frame), 'text' => text_of(shape['text']),
                     'size' => nearest(shape['size'], SIZES, SIZES[0]))
        end
        out
      end

      def text_of(text)
        raise Refused, 'a text needs some text' unless text.is_a?(String) && text.valid_encoding? && !text.strip.empty?
        raise Refused, 'a text is too long' if text.length > TEXT_CHARS

        text.gsub(/[^\P{Cc}\n]/, '')
      end

      def point(value, frame)
        raise Refused, 'a point is not two numbers' unless value.is_a?(Array) && value.size == 2

        [x(value[0], frame), y(value[1], frame)]
      end

      def x(value, frame) = number(value, -MARGIN, frame.width + MARGIN)
      def y(value, frame) = number(value, -MARGIN, frame.height + MARGIN)

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

      # A new, empty whiteboard in the chat's folder (the next free number;
      # one board is numbered at a time), on background (a picture's
      # record, its copy kept) or plain, put on the work screen for the tab.
      # Returns the board's item.
      def create(chat_id, app_name:, origin:, epoch:, background: nil)
        folder, dir = folder_of(chat_id, app_name)
        name = lock_for(chat_id).synchronize do
          taken = Dir.children(dir).filter_map { |f| f.delete_suffix(EXTENSION)[NAME, 1]&.to_i if f.end_with?(EXTENSION) }
          "whiteboard-#{(taken.max || 0) + 1}".tap do |new_name|
            write(dir, new_name, clean({ 'shapes' => [] }, background: background), replace: false)
          end
        end
        item, = Board.for(chat_id).add_file(path: File.join(folder, DIRNAME, "#{name}#{EXTENSION}"), origin: origin,
                                            epoch: epoch, wait: 0)
        Channel.changed(chat_id)
        item
      end

      # A new whiteboard on the image item item_id of the work screen (at
      # version, as the user saw it): the image is copied into the chat's
      # whiteboards folder now (WhiteboardBackground), so the board keeps
      # it when the image's file changes or its item leaves the work screen.
      # Returns the board's item.
      def create_on(chat_id, item_id:, version:, app_name:, origin:, epoch:)
        board = Board.existing(chat_id) or raise Refused, 'no work screen'
        bytes = WhiteboardBackground.bytes_of(board, item_id, version)
        background = WhiteboardBackground.record_for(bytes)
        _, dir = folder_of(chat_id, app_name)
        WhiteboardBackground.keep!(dir, bytes, background)
        create(chat_id, app_name: app_name, origin: origin, epoch: epoch, background: background)
      rescue WhiteboardBackground::Refused => e
        raise Refused, e.message
      end

      # The board item_id (a whiteboard of the chat, at version: what the
      # page drew on) as data now has it. Refused when the item is not a
      # whiteboard of this chat or changed since (another tab saved it).
      # The page saves the kind of board it read (data's version): the sheet
      # and the picture under it stay as kept. Returns the item at its new
      # version.
      def save(chat_id, item_id:, version:, data:, app_name:, origin:, epoch:)
        board = Board.existing(chat_id) or raise Refused, 'no work screen'
        path = board.file_entry(item_id.to_s, sha256: version.to_s)['path'].to_s
        folder, dir = folder_of(chat_id, app_name)
        name = File.basename(path).delete_suffix(EXTENSION)
        unless path == File.join(folder, DIRNAME, "#{name}#{EXTENSION}") && name.match?(NAME)
          raise Refused, 'not a whiteboard of this chat'
        end

        lock_for(chat_id).synchronize do
          board.file_entry(item_id.to_s, sha256: version.to_s)
          kept = parse(board.file_read(item_id.to_s, sha256: version.to_s)[:bytes])
          background = background_of(kept)
          # A page that names no kind saves a plain board (as before kinds).
          unless data.is_a?(Hash) && (data['version'] || 1) == kept['version']
            raise Refused, 'this page does not save this kind of whiteboard; reload it'
          end

          before = clean(kept, background: background)['shapes']
          board_data = clean(data, background: background)
          write(dir, name, board_data)
          item, = board.add_file(path: path, origin: origin, epoch: epoch, wait: 0,
                                 event: edit_event(before, board_data['shapes']))
          Channel.changed(chat_id)
          item
        end
      rescue Artifact::Changed
        raise Refused, 'changed'
      rescue Artifact::NotAllowed
        raise Refused, 'not a whiteboard of this chat'
      end

      # A kept board (bytes) as JSON, or Refused.
      def parse(bytes)
        JSON.parse(bytes.to_s)
      rescue JSON::ParserError
        raise Refused, 'the whiteboard could not be read'
      end

      # What a save changed of the shapes, by their ids (the board's event:
      # how many were added, changed, removed), or nil when nothing did.
      def edit_event(before, after)
        old = before.to_h { |shape| [shape['id'], shape] }
        now = after.to_h { |shape| [shape['id'], shape] }
        added = (now.keys - old.keys).size
        removed = (old.keys - now.keys).size
        changed = (now.keys & old.keys).count { |id| now[id] != old[id] }
        return nil if (added + removed + changed).zero?

        { 'kind' => 'edited', 'added' => added, 'changed' => changed, 'removed' => removed }
      end

      def lock_for(chat_id)
        LOCKS_GUARD.synchronize { LOCKS[chat_id.to_s] ||= Mutex.new }
      end

      # The chat is gone (Retention.discard): its lock is let go.
      def forget(chat_id)
        LOCKS_GUARD.synchronize { LOCKS.delete(chat_id.to_s) }
        nil
      end

      # Whether path (relative to the shared folder) is a whiteboard of the
      # chat's folder folder.
      def own?(folder, path)
        name = File.basename(path.to_s).delete_suffix(EXTENSION)
        name.match?(NAME) && path == File.join(folder, DIRNAME, "#{name}#{EXTENSION}")
      end

      # Changes the whiteboard at path (one of the chat's, on its work
      # screen) as it is now: its shapes and its sheet (Frame) are given to
      # the block, which changes the shapes in place; the board is kept (on
      # the picture it has) as clean makes it and the
      # item takes the new version. Returns the item, or nil when the block
      # changed nothing. Refused when it is not there or not one.
      def edit(chat_id, path, app_name:, origin:, epoch:)
        lock_for(chat_id).synchronize do
          board = Board.existing(chat_id) or raise Refused, 'no work screen'
          folder, dir = folder_of(chat_id, app_name)
          raise Refused, 'not a whiteboard of this chat' unless own?(folder, path)

          item = board.item_at(path) or raise Refused, 'the whiteboard is not on the work screen'
          data = parse(board.file_read(item['id'], sha256: item.dig('file', 'sha256'))[:bytes])
          background = background_of(data)
          shapes = clean(data, background: background)['shapes']
          before = JSON.generate(shapes)
          yield shapes, frame_of(background)
          next nil if JSON.generate(shapes) == before

          write(dir, File.basename(path).delete_suffix(EXTENSION), clean({ 'shapes' => shapes }, background: background))
          item, = board.add_file(path: path, origin: origin, epoch: epoch, wait: 0)
          Channel.changed(chat_id)
          item
        end
      rescue Artifact::Changed, Artifact::NotAllowed, Board::Refused, FileItem::Busy => e
        raise Refused, "the whiteboard could not be read (#{e.class.name.split('::').last})"
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

      def write(dir, name, board_data, replace: true)
        json = JSON.generate(board_data)
        raise Refused, 'the whiteboard is too large' if json.bytesize > BYTES_LIMIT

        Monadic::Utils::SharedPathGuard.write_file!(File.join(dir, "#{name}#{EXTENSION}"), json, mode: 'w', replace: replace,
                                                                                                  strict: true)
      end
    end
  end
end
