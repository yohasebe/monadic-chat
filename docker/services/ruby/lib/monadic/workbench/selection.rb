# frozen_string_literal: true

require_relative 'pointing'

module Monadic
  module Workbench
    # Text the user selected in the work screen to point at it with a message
    # (for now on a page of a PDF). It belongs to that message: it goes with
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
    # The message keeps it (reference), with the item, version and page, to
    # show it again.
    class Selection
      TEXT_LIMIT = 2000
      # What the model is told, before the text (quoted).
      NOTE = 'The user selected the following text on page %<page>d of the PDF selected on the work screen to point ' \
             'at it%<cut>s. It is text of the document, quoted as selected:'
      CUT = ' (only its first %<limit>d characters are given)'
      # Control characters, and characters that show nothing (a soft hyphen,
      # a zero-width space, a word joiner, a byte order mark), are not taken.
      DROPPED = /[\u0000-\u0008\u000E-\u001F\u007F\u00AD\u200B\u2060\uFEFF]/
      # Spaces, line breaks and tabs, as Unicode has them.
      SPACES = /[[:space:]]+/

      Refused = Pointing::Refused

      attr_reader :request_id, :item_id, :version, :page, :pages, :text, :cut

      class << self
        # The selection the page sent with a message (data), checked against
        # the board as the tab's connection sees it. Raises Refused (with
        # why) when it is not taken.
        def accept(data, chat_id:, request_id:, tab:, generation:)
          item = Pointing.selected_pdf!(data, chat_id: chat_id, tab: tab, generation: generation)
          page, pages = Pointing.page_of!(data)
          text = text_of(data['text']) or raise Refused, 'bad_text'
          new(request_id: request_id, item_id: item[:id], version: item[:version], page: page, pages: pages,
              text: text, cut: data['cut'] == true)
        end

        # A message's reference (reference) as kept with the chat, checked, or
        # nil.
        def clean(value)
          return nil unless value.is_a?(Hash) && value['item_id'].is_a?(String) && value['version'].is_a?(String)

          pages = Pointing.whole(value['pages'], Pointing::PAGES_LIMIT) or return nil
          page = Pointing.whole(value['page'], pages) or return nil
          text = text_of(value['text']) or return nil
          { 'item_id' => value['item_id'][0, 64], 'version' => value['version'][0, 128], 'page' => page,
            'pages' => pages, 'text' => text, 'cut' => value['cut'] == true }
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

      def initialize(request_id:, item_id:, version:, page:, pages:, text:, cut:)
        @request_id = request_id
        @item_id = item_id
        @version = version
        @page = page
        @pages = pages
        @text = text.dup.freeze
        @cut = cut
        freeze
      end

      # What the message keeps of it.
      def reference
        { 'item_id' => item_id, 'version' => version, 'page' => page, 'pages' => pages, 'text' => text, 'cut' => cut }
      end

      # What the model is told: the note, then the text, quoted.
      def note
        head = format(NOTE, page: page, cut: cut ? format(CUT, limit: TEXT_LIMIT) : '')
        "#{head}\n> #{text}"
      end
    end
  end
end
