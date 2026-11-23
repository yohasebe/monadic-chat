# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'securerandom'
require_relative 'board'
require_relative 'store'

module Monadic
  module Workbench
    # A picture of the work screen as the user had it when they sent a
    # message: the part of the selected PDF's page in view, with the part
    # they point at marked on it (the pointer). It belongs to that message:
    # it goes with the message's request, and with the requests that return
    # its tools' results, and with no later message's.
    #
    # The page takes it when the user sends; it is taken here only for the
    # item the user's tab has selected on the board, at the version the
    # board has, and only as a PNG of a bounded size. It is kept in the
    # chat's folder of the workbench store (not the shared folder), and
    # removed with its message.
    #
    # The message keeps a reference (reference): the item, version, page
    # and the mark, never the bytes.
    class Picture
      DIRNAME = 'pictures'
      PNG = "\x89PNG\r\n\x1A\n".b
      ID = /\Ap_\h{20}\z/
      # What is taken, at most (as the page cuts it).
      BASE64_LIMIT = 5 * 1024 * 1024
      SIDE_LIMIT = 2048
      PIXELS_LIMIT = 4_194_304
      PAGES_LIMIT = 100_000
      SHAPES = %w[rect ellipse].freeze
      # The colors a mark is drawn in (the page's palette, by name).
      COLORS = %w[orange magenta cyan green yellow].freeze
      # What the model is told with the picture.
      NOTE = 'The image attached to this message is the part of page %<page>d of the PDF selected on the work screen ' \
             'that the user had in view when sending. The user marked a part of it with a translucent %<color>s ' \
             '%<shape>s to point at it (left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the image).'

      class Refused < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      attr_reader :id, :chat_id, :request_id, :item_id, :version, :page, :pages, :mark, :bytes

      class << self
        # The picture the page sent with a message (data), checked against
        # the board as the tab's connection sees it. Raises Refused (with
        # why) when it is not taken.
        def accept(data, chat_id:, request_id:, tab:, generation:)
          raise Refused, 'not_a_picture' unless data.is_a?(Hash)

          board = Board.existing(chat_id) or raise Refused, 'no_board'
          seen = board.observe(tab: tab.to_s, generation: generation) or raise Refused, 'not_this_tab'
          item = seen[:items].find { |i| i[:id] == seen[:selected] }
          raise Refused, 'not_selected' unless item && item[:id] == data['item_id']
          raise Refused, 'not_a_pdf' unless item[:kind] == 'file' && item[:preview].to_s == 'pdf'
          raise Refused, 'changed' unless data['version'] == item[:version]

          pages = whole(data['pages'], PAGES_LIMIT) or raise Refused, 'bad_page'
          page = whole(data['page'], pages) or raise Refused, 'bad_page'
          mark = mark_of(data['mark']) or raise Refused, 'bad_mark'
          bytes = png_of(data['image'])
          new(id: "p_#{SecureRandom.hex(10)}", chat_id: chat_id, request_id: request_id, item_id: item[:id],
              version: item[:version], page: page, pages: pages, mark: mark, bytes: bytes)
        end

        # A message's reference (reference) as kept with the chat, checked, or
        # nil.
        def clean(value)
          return nil unless value.is_a?(Hash) && value['id'].is_a?(String) && value['id'].match?(ID)

          pages = whole(value['pages'], PAGES_LIMIT) or return nil
          page = whole(value['page'], pages) or return nil
          mark = mark_of(value['mark']) or return nil
          return nil unless value['item_id'].is_a?(String) && value['version'].is_a?(String)

          { 'id' => value['id'], 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128],
            'page' => page, 'pages' => pages, 'mark' => mark }
        end

        # The bytes of the picture id kept for chat_id, or nil.
        def read(chat_id, id, store: Store.default)
          path = path_of(chat_id, id, store: store) or return nil
          File.file?(path) ? File.binread(path) : nil
        end

        # Removes the picture id of chat_id (nothing when there is none).
        def remove(chat_id, id, store: Store.default)
          path = path_of(chat_id, id, store: store) or return
          FileUtils.rm_f(path)
        end

        def path_of(chat_id, id, store:)
          return nil unless id.is_a?(String) && id.match?(ID)

          File.join(store.chat_dir(chat_id), DIRNAME, "#{id}.png")
        rescue ArgumentError
          nil
        end

        private

        # An Integer from 1 to limit, or nil.
        def whole(value, limit)
          value.is_a?(Integer) && value.between?(1, limit) ? value : nil
        end

        # { shape, color, x, y, w, h } within the picture (fractions), or
        # nil. A mark with no color is orange.
        def mark_of(value)
          return nil unless value.is_a?(Hash) && SHAPES.include?(value['shape'])

          color = value.fetch('color', 'orange')
          return nil unless COLORS.include?(color)

          x, y, w, h = %w[x y w h].map { |k| value[k] }
          return nil unless [x, y, w, h].all? { |v| v.is_a?(Numeric) && v.to_f.finite? }
          return nil unless x >= 0 && y >= 0 && w.positive? && h.positive? && x + w <= 1.0001 && y + h <= 1.0001

          { 'shape' => value['shape'], 'color' => color, 'x' => x.to_f, 'y' => y.to_f, 'w' => w.to_f, 'h' => h.to_f }
        end

        # The PNG's bytes, within the size taken, or Refused.
        def png_of(value)
          raise Refused, 'bad_image' unless value.is_a?(String) && value.bytesize <= BASE64_LIMIT

          bytes = Base64.strict_decode64(value)
          raise Refused, 'bad_image' unless bytes.start_with?(PNG) && bytes.byteslice(12, 4) == 'IHDR'

          width, height = bytes.byteslice(16, 8).unpack('NN')
          raise Refused, 'bad_image' unless width.to_i.between?(1, SIDE_LIMIT) && height.to_i.between?(1, SIDE_LIMIT)
          raise Refused, 'bad_image' unless width * height <= PIXELS_LIMIT

          bytes
        rescue ArgumentError
          raise Refused, 'bad_image'
        end
      end

      def initialize(id:, chat_id:, request_id:, item_id:, version:, page:, pages:, mark:, bytes:)
        @id = id
        @chat_id = chat_id
        @request_id = request_id
        @item_id = item_id
        @version = version
        @page = page
        @pages = pages
        @mark = mark.freeze
        @bytes = bytes.dup.freeze
        freeze
      end

      # Writes the picture into the chat's folder of the store (0600; a
      # whole file or none).
      def keep!(store: Store.default)
        dir = File.join(store.chat_dir(chat_id, make: true), DIRNAME)
        FileUtils.mkdir_p(dir, mode: 0o700)
        path = File.join(dir, "#{id}.png")
        temp = "#{path}.#{SecureRandom.hex(4)}.tmp"
        File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(bytes) }
        File.rename(temp, path)
        self
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      # What the message keeps of it.
      def reference
        { 'id' => id, 'item_id' => item_id, 'version' => version, 'page' => page, 'pages' => pages, 'mark' => mark.dup }
      end

      # The picture as an image of a message, for the request.
      def image
        { 'title' => 'work-screen.png', 'type' => 'image/png',
          'data' => "data:image/png;base64,#{Base64.strict_encode64(bytes)}", 'workbench_picture' => true }
      end

      # What the model is told with it.
      def note
        format(NOTE, page: page, shape: mark['shape'] == 'ellipse' ? 'ellipse' : 'rectangle',
                     color: COLORS.include?(mark['color']) ? mark['color'] : 'orange',
                     x: (mark['x'] * 100).round, y: (mark['y'] * 100).round,
                     w: (mark['w'] * 100).round, h: (mark['h'] * 100).round)
      end
    end
  end
end
