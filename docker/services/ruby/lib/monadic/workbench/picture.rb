# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'securerandom'
require_relative 'pointing'
require_relative 'store'

module Monadic
  module Workbench
    # A picture of the work screen as the user had it when they sent a
    # message: the part of the selected PDF's page in view, or the selected
    # image, with the part they point at marked on it (the pointer); for a
    # model that cannot look at the work screen itself (no tools), unmarked
    # when the user marked nothing. It belongs to that message:
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
    # (of a PDF; an image's has kind 'image' instead) and the mark, never
    # the bytes; and, once a request with it was handed to the provider,
    # the sha256 of the image kept as sent (Sent).
    class Picture
      DIRNAME = 'pictures'
      PNG = "\x89PNG\r\n\x1A\n".b
      ID = /\Ap_\h{20}\z/
      # What is taken, at most (as the page cuts it).
      BASE64_LIMIT = 5 * 1024 * 1024
      SIDE_LIMIT = 2048
      PIXELS_LIMIT = 4_194_304
      PAGES_LIMIT = Pointing::PAGES_LIMIT
      SHAPES = Pointing::SHAPES
      # The colors a mark is drawn in (the page's palette, by name).
      COLORS = Pointing::COLORS
      # What the model is told with the picture.
      NOTE = 'The image attached to this message is the part of page %<page>d of the PDF selected on the work screen ' \
             'that the user had in view when sending. The user marked a part of it with a translucent %<color>s ' \
             '%<shape>s to point at it (left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the image).'
      NOTE_IMAGE = 'The image attached to this message is the image selected on the work screen when the user sent it. ' \
                   'The user marked a part of it with a translucent %<color>s %<shape>s to point at it ' \
                   '(left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the image).'
      NOTE_PLAIN = 'The image attached to this message is the part of page %<page>d of the PDF selected on the work screen ' \
                   'that the user had in view when sending.'
      NOTE_IMAGE_PLAIN = 'The image attached to this message is the image selected on the work screen when the user sent it.'

      Refused = Pointing::Refused

      attr_reader :id, :chat_id, :request_id, :item_id, :version, :kind, :page, :pages, :mark, :bytes

      class << self
        # The picture the page sent with a message (data), checked against
        # the board as the tab's connection sees it. Raises Refused (with
        # why) when it is not taken. unmarked: an unmarked picture is taken
        # (the model cannot look at the work screen itself).
        def accept(data, chat_id:, request_id:, tab:, generation:, unmarked: false)
          item = Pointing.selected!(data, chat_id: chat_id, tab: tab, generation: generation, previews: %w[pdf image])
          kind = item[:preview].to_s
          page, pages = kind == 'pdf' ? Pointing.page_of!(data) : [nil, nil]
          mark = if data['unmarked'] == true
                   raise Refused, 'unmarked' unless unmarked

                   nil
                 else
                   Pointing.mark_of(data['mark']) or raise Refused, 'bad_mark'
                 end
          bytes = png_of(data['image'])
          new(id: "p_#{SecureRandom.hex(10)}", chat_id: chat_id, request_id: request_id, item_id: item[:id],
              version: item[:version], kind: kind, page: page, pages: pages, mark: mark, bytes: bytes)
        end

        # A message's reference (reference) as kept with the chat, checked, or
        # nil.
        def clean(value)
          return nil unless value.is_a?(Hash) && value['id'].is_a?(String) && value['id'].match?(ID)

          marked = if value['unmarked'] == true
                     { 'unmarked' => true }
                   else
                     mark = Pointing.mark_of(value['mark']) or return nil
                     { 'mark' => mark }
                   end
          return nil unless value['item_id'].is_a?(String) && value['version'].is_a?(String)

          out = { 'id' => value['id'], 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128] }
          out['sha256'] = value['sha256'] if value['sha256'].is_a?(String) && value['sha256'].match?(/\A\h{64}\z/)
          return out.merge('kind' => 'image').merge(marked) if value['kind'] == 'image'

          pages = Pointing.whole(value['pages'], PAGES_LIMIT) or return nil
          page = Pointing.whole(value['page'], pages) or return nil
          out.merge('page' => page, 'pages' => pages).merge(marked)
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

      def initialize(id:, chat_id:, request_id:, item_id:, version:, page:, pages:, mark:, bytes:, kind: 'pdf')
        @id = id
        @chat_id = chat_id
        @request_id = request_id
        @item_id = item_id
        @version = version
        @kind = kind
        @page = page
        @pages = pages
        @mark = mark&.freeze
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
        out = { 'id' => id, 'item_id' => item_id, 'version' => version }
        marked = mark ? { 'mark' => mark.dup } : { 'unmarked' => true }
        return out.merge('kind' => 'image').merge(marked) if kind == 'image'

        out.merge('page' => page, 'pages' => pages).merge(marked)
      end

      # The picture as an image of a message, for the request.
      def image
        { 'title' => 'work-screen.png', 'type' => 'image/png',
          'data' => "data:image/png;base64,#{Base64.strict_encode64(bytes)}", 'workbench_picture' => true }
      end

      # What the model is told with it.
      def note
        return format(kind == 'image' ? NOTE_IMAGE_PLAIN : NOTE_PLAIN, page: page) unless mark

        format(kind == 'image' ? NOTE_IMAGE : NOTE, page: page, shape: mark['shape'] == 'ellipse' ? 'ellipse' : 'rectangle',
                     color: COLORS.include?(mark['color']) ? mark['color'] : 'orange',
                     x: (mark['x'] * 100).round, y: (mark['y'] * 100).round,
                     w: (mark['w'] * 100).round, h: (mark['h'] * 100).round)
      end
    end
  end
end
