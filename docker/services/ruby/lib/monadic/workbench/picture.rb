# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'securerandom'
require_relative 'pointing'
require_relative 'store'
require_relative '../utils/privacy/outbound'

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
      # Pictures of marked items, several with one message (accept_marked).
      PER_MESSAGE = 4
      # named: ' "the item's name"', or nothing when it is not told (name_for).
      NOTE_MARKED = 'Work screen picture %<n>d attached to this message is page %<page>d of the PDF%<named>s ' \
                    '(work screen item %<item>s). The user marked a part of it with a translucent %<color>s %<shape>s ' \
                    'to point at it (left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the page).'
      NOTE_MARKED_IMAGE = 'Work screen picture %<n>d attached to this message is the image%<named>s ' \
                          '(work screen item %<item>s). The user marked a part of it with a translucent %<color>s ' \
                          '%<shape>s to point at it (left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the image).'
      # A mark's own id (the page's), and how many times it changed.
      MARK_ID = /\Am_[a-z0-9]{6,32}\z/
      REV_LIMIT = 1_000_000
      NAME_LIMIT = 120
      # Where a picture of a marked item may be: on the desk, where marks are made.
      MARKABLE_PLACES = %w[current latest].freeze

      Refused = Pointing::Refused

      attr_reader :id, :chat_id, :request_id, :item_id, :version, :kind, :page, :pages, :mark, :bytes,
                  :name, :mark_id, :mark_rev, :position

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

        # The pictures of the marked items the page sent with a message (list:
        # each the whole image, or the whole page of a PDF, with the mark
        # drawn on it), checked against the board as the tab's connection
        # sees it: each item on the desk where marks are made (Now, Latest),
        # at the version the board has, a file that shows an image or a PDF
        # (or an image the AI made), once per item and page. Raises Refused
        # (with why) when one is not taken: none is taken then. They are not
        # kept until the message is accepted (keep!).
        # words: the words the chat hides (nil: not known); a name that holds
        # one is not told, nor any name when they are not known.
        def accept_marked(list, chat_id:, request_id:, tab:, generation:, words: [])
          raise Refused, 'not_a_picture' unless list.is_a?(Array) && !list.empty?
          raise Refused, 'too_many' if list.size > PER_MESSAGE

          board = Board.existing(chat_id) or raise Refused, 'no_board'
          seen = board.observe(tab: tab.to_s, generation: generation) or raise Refused, 'not_this_tab'
          items = seen[:items].to_h { |item| [item[:id], item] }
          taken = {}
          list.each_with_index.map do |data, index|
            raise Refused, 'not_a_picture' unless data.is_a?(Hash)

            item = items[data['item_id']] or raise Refused, 'not_on_screen'
            raise Refused, 'put_away' if item[:place] == 'stash'
            raise Refused, 'not_markable' unless MARKABLE_PLACES.include?(item[:place].to_s)

            kind = kind_of(item) or raise Refused, 'not_pointable'
            raise Refused, 'changed' unless data['version'] == item[:version]

            page, pages = kind == 'pdf' ? Pointing.page_of!(data) : [nil, nil]
            raise Refused, 'twice' if taken[[item[:id], page]]

            taken[[item[:id], page]] = true
            mark = Pointing.mark_of(data['mark']) or raise Refused, 'bad_mark'
            mark_id = data['mark_id'].is_a?(String) && data['mark_id'].match?(MARK_ID) ? data['mark_id'] : nil
            raise Refused, 'bad_mark' unless mark_id && data['mark_rev'].is_a?(Integer) && data['mark_rev'].between?(0, REV_LIMIT)

            new(id: "p_#{SecureRandom.hex(10)}", chat_id: chat_id, request_id: request_id, item_id: item[:id],
                version: item[:version], kind: kind, page: page, pages: pages, mark: mark, bytes: png_of(data['image']),
                name: name_for(item, words), mark_id: mark_id, mark_rev: data['mark_rev'], position: index + 1)
          end
        end

        # The references a message keeps of the pictures it was sent with,
        # as kept (workbench_pictures; a message from before, its one
        # workbench_picture).
        def references_of(message)
          return [] unless message.is_a?(Hash)

          list = message['workbench_pictures']
          return list.select { |ref| ref.is_a?(Hash) } if list.is_a?(Array)

          message['workbench_picture'].is_a?(Hash) ? [message['workbench_picture']] : []
        end

        # The references of a message (references_of), each checked (clean),
        # at most PER_MESSAGE: what a history, an export or an import keeps,
        # always as workbench_pictures.
        def clean_all(message)
          references_of(message).filter_map { |ref| clean(ref) }.uniq { |ref| ref['id'] }.first(PER_MESSAGE)
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
          if value['mark_id'].is_a?(String) && value['mark_id'].match?(MARK_ID) &&
             value['mark_rev'].is_a?(Integer) && value['mark_rev'].between?(0, REV_LIMIT)
            out['mark_id'] = value['mark_id']
            out['mark_rev'] = value['mark_rev']
          end
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

        # What a marked item's picture is: an image (a file that shows one,
        # or one the AI made) or a PDF; nil for anything else.
        def kind_of(item)
          return 'image' if item[:kind] == 'image'
          return nil unless item[:kind] == 'file'

          { 'image' => 'image', 'pdf' => 'pdf' }[item[:preview].to_s]
        end

        # The item's name as the model is told it: one line, every kind of
        # space as a space, cut at a word's end; nil when the whole name holds
        # a word the chat hides (the picture is then named by its item only,
        # as the observation leaves such a name out).
        def name_for(item, words)
          name = (item[:title] || item[:name]).to_s.scrub('?').gsub(/[\p{Cc}\p{Cf}\p{Z}"]/, ' ').squeeze(' ').strip
          return nil if name.empty? || words.nil?
          return nil if !words.empty? && Monadic::Utils::Privacy::Outbound.leaks_word?(name, words)
          return name if name.length <= NAME_LIMIT

          cut = name[0, NAME_LIMIT]
          cut = cut[0, cut.rindex(' ')] if name[NAME_LIMIT] != ' ' && cut.include?(' ')
          "#{cut.rstrip}…"
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

      def initialize(id:, chat_id:, request_id:, item_id:, version:, page:, pages:, mark:, bytes:, kind: 'pdf',
                     name: nil, mark_id: nil, mark_rev: nil, position: 1)
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
        @name = name&.freeze
        @mark_id = mark_id&.freeze
        @mark_rev = mark_rev
        @position = position
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
        if mark_id
          out['mark_id'] = mark_id
          out['mark_rev'] = mark_rev
        end
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

        if mark_id
          return format(kind == 'image' ? NOTE_MARKED_IMAGE : NOTE_MARKED, n: position, page: page,
                                                                         named: name ? %( "#{name}") : '',
                                                                         item: item_id, **mark_terms)
        end

        format(kind == 'image' ? NOTE_IMAGE : NOTE, page: page, **mark_terms)
      end

      # The mark as the notes say it.
      def mark_terms
        { shape: mark['shape'] == 'ellipse' ? 'ellipse' : 'rectangle',
          color: COLORS.include?(mark['color']) ? mark['color'] : 'orange',
          x: (mark['x'] * 100).round, y: (mark['y'] * 100).round,
          w: (mark['w'] * 100).round, h: (mark['h'] * 100).round }
      end
    end
  end
end
