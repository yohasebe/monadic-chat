# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'securerandom'
require 'json'
require_relative 'pointing'
require_relative 'whiteboard'
require_relative 'whiteboard_background'
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
      NOTE_MARKED = 'Work screen picture %<n>d attached to this message is the part of page %<page>d of the PDF%<named>s ' \
                    '(work screen item %<item>s) the user had in view when marking it. The user marked a part of it ' \
                    'with a translucent %<color>s %<shape>s to point at it ' \
                    '(left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the picture).'
      NOTE_MARKED_IMAGE = 'Work screen picture %<n>d attached to this message is the image%<named>s ' \
                          '(work screen item %<item>s). The user marked a part of it with a translucent %<color>s ' \
                          '%<shape>s to point at it (left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%% of the image).'
      # Marks on one picture at most.
      MARKS_LIMIT = 8
      # An image the user drew on, with no mark, and the words added when it
      # has marks too.
      NOTE_DRAWN_IMAGE = 'Work screen picture %<n>d attached to this message is the image%<named>s (work screen item %<item>s). ' \
                         'The user drew on it (lines, arrows, shapes and text, as drawn) to show you what they mean.'
      NOTE_DRAWN_TOO = 'The user also drew on it (lines, arrows, shapes and text, as drawn).'
      NOTE_SEVERAL = 'Work screen picture %<n>d attached to this message is the part of page %<page>d of the PDF%<named>s ' \
                     '(work screen item %<item>s) the user had in view when marking it. The user marked %<count>d parts of it, ' \
                     'each translucent and numbered on the picture: %<marks>s (as fractions of the picture).'
      NOTE_SEVERAL_IMAGE = 'Work screen picture %<n>d attached to this message is the image%<named>s (work screen item %<item>s). ' \
                           'The user marked %<count>d parts of it, each translucent and numbered on the picture: ' \
                           '%<marks>s (as fractions of the image).'
      MARK_TERM = 'mark %<number>d, a %<color>s %<shape>s at left %<x>d%%, top %<y>d%%, width %<w>d%%, height %<h>d%%'
      # A mark's own id (the page's), and how many times it changed.
      MARK_ID = /\Am_[a-z0-9]{6,32}\z/
      REV_LIMIT = 1_000_000
      NAME_LIMIT = 120
      # Where a picture of a marked item may be: on the desk, where marks are made.
      MARKABLE_PLACES = %w[current latest].freeze

      Refused = Pointing::Refused

      attr_reader :id, :chat_id, :request_id, :item_id, :version, :kind, :page, :pages, :mark, :bytes,
                  :name, :mark_id, :mark_rev, :position, :rect, :mark_list, :drawing

      class << self
        # The picture the page sent with a message (data), checked against
        # the board as the tab's connection sees it. Raises Refused (with
        # why) when it is not taken. unmarked: an unmarked picture is taken
        # (the model cannot look at the work screen itself).
        def accept(data, chat_id:, request_id:, tab:, generation:, unmarked: false, words: [])
          item = Pointing.selected!(data, chat_id: chat_id, tab: tab, generation: generation, previews: %w[pdf image])
          board_words!(chat_id, item[:id], words)
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
        # each the whole image, or the part of a PDF's page in view when the
        # mark was made, with the mark drawn on it; the mark's place is a
        # fraction of the picture), checked against the board as the tab's connection
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
            board_words!(chat_id, item[:id], words)
            raise Refused, 'not_markable' unless MARKABLE_PLACES.include?(item[:place].to_s)

            kind = kind_of(item) or raise Refused, 'not_pointable'
            raise Refused, 'changed' unless data['version'] == item[:version]

            page, pages = kind == 'pdf' ? Pointing.page_of!(data) : [nil, nil]
            raise Refused, 'twice' if taken[[item[:id], page]]

            taken[[item[:id], page]] = true
            # What the user drew on an image (checked against it), and the
            # marks on it, numbered as drawn (marks), or the one mark of a
            # page from before (mark, mark_id, mark_rev, rect). A drawing
            # may go with no mark.
            drawing = drawing_of(data, kind, board, item, words)
            marks = drawing && data['marks'] == [] ? [] : marks_of(data)
            first = marks.first || {}
            new(id: "p_#{SecureRandom.hex(10)}", chat_id: chat_id, request_id: request_id, item_id: item[:id],
                version: item[:version], kind: kind, page: page, pages: pages, mark: first['mark'], bytes: png_of(data['image']),
                name: name_for(item, words), mark_id: first['id'], mark_rev: first['rev'], position: index + 1,
                rect: first['rect'], marks: marks, drawing: drawing)
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
                   elsif value['drawn'] == true && !value.key?('mark')
                     {}
                   else
                     mark = Pointing.mark_of(value['mark']) or return nil
                     { 'mark' => mark }
                   end
          return nil unless value['item_id'].is_a?(String) && value['version'].is_a?(String)

          out = { 'id' => value['id'], 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128] }
          out['drawn'] = true if value['drawn'] == true
          out['sha256'] = value['sha256'] if value['sha256'].is_a?(String) && value['sha256'].match?(/\A\h{64}\z/)
          if value['mark_id'].is_a?(String) && value['mark_id'].match?(MARK_ID) &&
             value['mark_rev'].is_a?(Integer) && value['mark_rev'].between?(0, REV_LIMIT)
            out['mark_id'] = value['mark_id']
            out['mark_rev'] = value['mark_rev']
          end
          several = several_of(value['marks'])
          out['marks'] = several if several
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

        # The marks a reference keeps when it has several, checked, or nil.
        def several_of(list)
          return nil unless list.is_a?(Array) && list.size.between?(2, MARKS_LIMIT)

          marks = list.map do |m|
            return nil unless m.is_a?(Hash) && m['id'].is_a?(String) && m['id'].match?(MARK_ID) &&
                              m['rev'].is_a?(Integer) && m['rev'].between?(0, REV_LIMIT)

            mark = Pointing.mark_of(m['mark']) or return nil
            { 'id' => m['id'], 'rev' => m['rev'], 'mark' => mark }
          end
          marks.map { |m| m['id'] }.uniq.size == marks.size ? marks : nil
        end

        def path_of(chat_id, id, store:)
          return nil unless id.is_a?(String) && id.match?(ID)

          File.join(store.chat_dir(chat_id), DIRNAME, "#{id}.png")
        rescue ArgumentError
          nil
        end

        private

        # The marks a picture carries, each { 'id', 'rev', 'mark' (its place on
        # the picture), 'rect' (on the whole image or page, or nil) }, at most
        # MARKS_LIMIT, ids once; Refused when one is not a mark.
        def marks_of(data)
          list = data['marks'].is_a?(Array) ? data['marks'] : [data.slice('mark', 'mark_id', 'mark_rev', 'rect').merge('legacy' => true)]
          raise Refused, 'bad_mark' if list.empty? || list.size > MARKS_LIMIT

          marks = list.map do |entry|
            raise Refused, 'bad_mark' unless entry.is_a?(Hash)

            legacy = entry['legacy']
            mark = Pointing.mark_of(entry['mark']) or raise Refused, 'bad_mark'
            id = legacy ? entry['mark_id'] : entry['id']
            rev = legacy ? entry['mark_rev'] : entry['rev']
            raise Refused, 'bad_mark' unless id.is_a?(String) && id.match?(MARK_ID) && rev.is_a?(Integer) && rev.between?(0, REV_LIMIT)

            rect = nil
            if entry.key?('rect')
              rect = Pointing.mark_of(entry['rect'].is_a?(Hash) ? entry['rect'].merge('shape' => mark['shape']) : nil)
              raise Refused, 'bad_mark' if rect.nil?
            end
            { 'id' => id, 'rev' => rev, 'mark' => mark, 'rect' => rect&.slice('x', 'y', 'w', 'h') }
          end
          raise Refused, 'bad_mark' unless marks.map { |m| m['id'] }.uniq.size == marks.size

          marks
        end

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
        # The shapes the user drew on an image item (data['drawing']['shapes']),
        # as a board drawn on that image keeps them (Whiteboard.clean, the
        # sheet from the image's own size), or nil when none was sent.
        # Refused: 'bad_drawing' for none that is one, or not on an image;
        # 'hides_words' when a text of it holds a word the chat hides, or
        # the words are not known.
        def drawing_of(data, kind, board, item, words)
          return nil unless data.key?('drawing')

          given = data['drawing']
          raise Refused, 'bad_drawing' unless kind == 'image' && given.is_a?(Hash) && given['shapes'].is_a?(Array) && !given['shapes'].empty?
          raise Refused, 'bad_drawing' if JSON.generate(given['shapes']).bytesize > Whiteboard::BYTES_LIMIT

          record = WhiteboardBackground.record_for(WhiteboardBackground.bytes_of(board, item[:id], item[:version]))
          shapes = Whiteboard.clean({ 'version' => 2, 'shapes' => given['shapes'] }, background: record)['shapes']
          raise Refused, 'bad_drawing' if shapes.empty?

          texts = shapes.filter_map { |shape| shape['text'] if shape['text'].is_a?(String) && !shape['text'].empty? }
          leaks = ->(text) { Monadic::Utils::Privacy::Outbound.leaks_word?(text, words) }
          raise Refused, 'hides_words' if !texts.empty? && (words.nil? || (!words.empty? && texts.any?(&leaks)))

          shapes
        rescue Whiteboard::Refused, WhiteboardBackground::Refused
          raise Refused, 'bad_drawing'
        end

        # An image made of a whiteboard whose texts hold a word the chat hides
        # (or whose words are not known) is not taken: 'hides_words'.
        def board_words!(chat_id, item_id, words)
          board = Board.existing(chat_id) or return
          raise Refused, 'hides_words' unless board.board_texts_clear?(item_id, words)
        end

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
                     name: nil, mark_id: nil, mark_rev: nil, position: 1, rect: nil, marks: nil, drawing: nil)
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
        @rect = rect&.freeze
        @mark_list = (marks || (mark_id ? [{ 'id' => mark_id, 'rev' => mark_rev, 'mark' => mark, 'rect' => rect }] : [])).freeze
        # The shapes the user drew on the image with this message, or nil.
        @drawing = drawing&.freeze
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
        if mark_list.size > 1
          out['marks'] = mark_list.map { |m| { 'id' => m['id'], 'rev' => m['rev'], 'mark' => m['mark'].dup } }
        end
        if mark_id
          out['mark_id'] = mark_id
          out['mark_rev'] = mark_rev
        end
        out['drawn'] = true if drawing
        marked = if mark then { 'mark' => mark.dup }
                 elsif drawing then {}
                 else { 'unmarked' => true }
                 end
        return out.merge('kind' => 'image').merge(marked) if kind == 'image'

        out.merge('page' => page, 'pages' => pages).merge(marked)
      end

      # The picture as an image of a message, for the request.
      def image
        { 'title' => 'work-screen.png', 'type' => 'image/png',
          'data' => "data:image/png;base64,#{Base64.strict_encode64(bytes)}", 'workbench_picture' => true }
      end

      # What the model is told with it: its marks, and that the user drew on
      # it (the drawing is read in the picture).
      def note
        return marks_note unless drawing
        return "#{marks_note} #{NOTE_DRAWN_TOO}" if mark

        format(NOTE_DRAWN_IMAGE, n: position, named: name ? %( "#{name}") : '', item: item_id)
      end

      def marks_note
        return format(kind == 'image' ? NOTE_IMAGE_PLAIN : NOTE_PLAIN, page: page) unless mark

        if mark_id
          named = name ? %( "#{name}") : ''
          return format(kind == 'image' ? NOTE_MARKED_IMAGE : NOTE_MARKED, n: position, page: page, named: named,
                                                                         item: item_id, **mark_terms) if mark_list.size <= 1

          return format(kind == 'image' ? NOTE_SEVERAL_IMAGE : NOTE_SEVERAL, n: position, page: page, named: named,
                                                                           item: item_id, count: mark_list.size,
                                                                           marks: several_terms)
        end

        format(kind == 'image' ? NOTE_IMAGE : NOTE, page: page, **mark_terms)
      end

      # The marks it carries as the board keeps them (where each is on the
      # whole image or page); none for a picture without that.
      def marks
        mark_list.select { |m| m['rect'] }.map do |m|
          { 'id' => m['id'], 'rev' => m['rev'], 'shape' => m['mark']['shape'], 'color' => m['mark']['color'], 'rect' => m['rect'].dup }
        end
      end

      # Each of several marks as the notes say it, by its number.
      def several_terms
        mark_list.each_with_index.map do |m, i|
          format(MARK_TERM, number: i + 1, **mark_terms(m['mark']))
        end.join('; ')
      end

      # The mark as the notes say it.
      def mark_terms(mark = self.mark)
        { shape: mark['shape'] == 'ellipse' ? 'ellipse' : 'rectangle',
          color: COLORS.include?(mark['color']) ? mark['color'] : 'orange',
          x: (mark['x'] * 100).round, y: (mark['y'] * 100).round,
          w: (mark['w'] * 100).round, h: (mark['h'] * 100).round }
      end
    end
  end
end
