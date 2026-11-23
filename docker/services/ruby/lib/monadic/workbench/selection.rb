# frozen_string_literal: true

require_relative 'pointing'
require_relative '../workspace/shared_folder_preview'

module Monadic
  module Workbench
    # Text the user selected in the work screen to point at it with a message:
    # on a page of a PDF, or lines of a text file. It belongs to that message: it goes with
    # the message's requests, quoted after what the user wrote, and with no
    # later message's. Being in the user's message, it is anonymized as what
    # they wrote is.
    #
    # The page sends it when the user sends, as they selected it; it is taken
    # only for the item the tab has selected on the board, at the version the
    # board has, and only up to TEXT_LIMIT characters (the page cuts a longer
    # selection and says so, cut). It is taken as one line: every run of
    # spaces (line breaks and no-break spaces among them) is one space, and
    # characters that show nothing are dropped, so that a word the chat hides
    # is found in it however the selection broke it.
    #
    # Lines of a text file are taken by their numbers: the page says which
    # (first, last), and the lines are read here from the file at the
    # board's version, as they are (line breaks and indentation kept), up
    # to LINES_LIMIT lines and LINES_CHARS characters; characters that show
    # nothing are dropped.
    #
    # The message keeps it (reference), with the item, version and page (or
    # kind 'text' and the lines' numbers), to show it again.
    class Selection
      TEXT_LIMIT = 2000
      # What the model is told, before the text (quoted).
      NOTE = 'The user selected the following text on page %<page>d of the PDF selected on the work screen to point ' \
             'at it%<cut>s. It is text of the document, quoted as selected:'
      CUT = ' (only its first %<limit>d characters are given)'
      LINES_LIMIT = 400
      LINES_CHARS = 8000
      NOTE_LINES = 'The user selected %<lines>s of the text file selected on the work screen to point at them. ' \
                   'They are lines of the file, quoted as they are:'
      LINES = 'lines %<first>d to %<last>d'
      CUT_LINES = 'lines starting at line %<first>d (only lines %<first>d to %<last>d are given)'
      # Control characters, and characters that show nothing (a soft hyphen,
      # a zero-width space, a word joiner, a byte order mark), are not taken.
      DROPPED = /[\u0000-\u0008\u000E-\u001F\u007F\u00AD\u200B\u2060\uFEFF]/
      # Spaces, line breaks and tabs, as Unicode has them.
      SPACES = /[[:space:]]+/

      Refused = Pointing::Refused

      attr_reader :request_id, :item_id, :version, :kind, :page, :pages, :first, :last, :text, :cut

      class << self
        # The selection the page sent with a message (data), checked against
        # the board as the tab's connection sees it. Raises Refused (with
        # why) when it is not taken.
        def accept(data, chat_id:, request_id:, tab:, generation:)
          item = Pointing.selected!(data, chat_id: chat_id, tab: tab, generation: generation, previews: %w[pdf text])
          return accept_lines(item, data, chat_id: chat_id, request_id: request_id) if item[:preview].to_s == 'text'

          page, pages = Pointing.page_of!(data)
          text = text_of(data['text']) or raise Refused, 'bad_text'
          new(request_id: request_id, item_id: item[:id], version: item[:version], page: page, pages: pages,
              text: text, cut: data['cut'] == true)
        end

        # A message's reference (reference) as kept with the chat, checked, or
        # nil.
        def clean(value)
          return nil unless value.is_a?(Hash) && value['item_id'].is_a?(String) && value['version'].is_a?(String)
          return clean_lines(value) if value['kind'] == 'text'

          pages = Pointing.whole(value['pages'], Pointing::PAGES_LIMIT) or return nil
          page = Pointing.whole(value['page'], pages) or return nil
          text = text_of(value['text']) or return nil
          { 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128], 'page' => page,
            'pages' => pages, 'text' => text, 'cut' => value['cut'] == true }
        end

        # The lines first..last of the text file item (the selected one, at
        # the board's version), read here, as a Selection.
        def accept_lines(item, data, chat_id:, request_id:)
          first = data['first']
          last = data['last']
          raise Refused, 'bad_lines' unless first.is_a?(Integer) && last.is_a?(Integer) && first.between?(1, last)

          board = Board.existing(chat_id) or raise Refused, 'no_board'
          preview = Monadic::Workspace::SharedFolderPreview
          lines = preview.text_lines(preview.text_view(board.file_read(item[:id], sha256: item[:version])[:bytes])[:text])
          raise Refused, 'bad_lines' if last > lines.size

          taken = take_lines(lines, first, last)
          new(request_id: request_id, item_id: item[:id], version: item[:version], kind: 'text', first: first,
              last: taken[:last], text: taken[:text], cut: taken[:cut])
        rescue Refused
          raise
        rescue StandardError
          raise Refused, 'unreadable'
        end

        # Lines first..last of lines (a text's, last within them), as they
        # are taken: whole lines from first, at most LINES_LIMIT of them and
        # LINES_CHARS characters, characters that show nothing dropped:
        # { text:, last: (the last given), cut: }.
        def take_lines(lines, first, last)
          taken = lines[(first - 1)...last].map { |line| line.gsub(DROPPED, '') }
          taken.pop while taken.size > 1 && (taken.size > LINES_LIMIT || taken.join("\n").length > LINES_CHARS)
          given = first + taken.size - 1
          { text: taken.join("\n")[0, LINES_CHARS], last: given, cut: given < last }
        end

        def clean_lines(value)
          first = value['first']
          last = value['last']
          return nil unless first.is_a?(Integer) && last.is_a?(Integer) && first.between?(1, last)
          return nil unless value['text'].is_a?(String) && value['text'].valid_encoding? && value['text'].length <= LINES_CHARS

          { 'kind' => 'text', 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128], 'first' => first,
            'last' => last, 'text' => value['text'].gsub(DROPPED, ''), 'cut' => value['cut'] == true }
        end

        # The text as one line (each run of spaces one space, nothing that
        # shows nothing), when it is some text within the limit; nil
        # otherwise.
        def text_of(value)
          return nil unless value.is_a?(String) && value.valid_encoding?

          text = value.gsub(DROPPED, '').gsub(SPACES, ' ').strip
          text.empty? || text.length > TEXT_LIMIT ? nil : text
        end
      end

      def initialize(request_id:, item_id:, version:, text:, cut:, kind: 'pdf', page: nil, pages: nil, first: nil, last: nil)
        @request_id = request_id
        @item_id = item_id
        @version = version
        @kind = kind
        @page = page
        @pages = pages
        @first = first
        @last = last
        @text = text.dup.freeze
        @cut = cut
        freeze
      end

      # What the message keeps of it.
      def reference
        if kind == 'text'
          return { 'kind' => 'text', 'item_id' => item_id, 'version' => version, 'first' => first, 'last' => last,
                   'text' => text, 'cut' => cut }
        end

        { 'item_id' => item_id, 'version' => version, 'page' => page, 'pages' => pages, 'text' => text, 'cut' => cut }
      end

      # What the model is told: the note, then the text, quoted.
      def note
        return lines_note if kind == 'text'

        head = format(NOTE, page: page, cut: cut ? format(CUT, limit: TEXT_LIMIT) : '')
        "#{head}\n> #{text}"
      end

      private

      # The lines in a fence longer than any run of backticks in them.
      def lines_note
        head = format(NOTE_LINES, lines: format(cut ? CUT_LINES : LINES, first: first, last: last))
        fence = '`' * [3, (text.scan(/`+/).map(&:length).max || 0) + 1].max
        "#{head}\n#{fence}\n#{text}\n#{fence}"
      end
    end
  end
end
