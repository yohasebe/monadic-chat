# frozen_string_literal: true

require 'json'
require_relative 'board'
require_relative 'look'
require_relative 'pdf_text'
require_relative 'shown'
require_relative '../shell'
require_relative '../workspace/shared_folder_preview'

module Monadic
  module Workbench
    # The AI points at a part of the item the asking tab shows in the work
    # screen (point_at_workbench): lines of a text file, by their numbers or
    # by a quote, or a quote on a page of a PDF. The place is found here, in
    # the item itself at the board's version (a quote, with any run of space
    # in it matching any run of space); the AI gives no position of its own.
    # The tab is told (transport), and the reply records it (Shown), so the
    # line under its message points there again.
    module Point
      LABEL_CHARS = 40
      QUOTE_CHARS = 300
      # Pages of a PDF a quote is looked for in, at most.
      PDF_PAGES = 100
      DEADLINE = 20

      class Refused < StandardError; end

      # How the tab is told: (tab, generation, chat_id, json) → true when
      # written to that connection. Set by the WebSocket layer.
      @transport = nil

      class << self
        attr_accessor :transport
      end

      module_function

      # Points for caller at the place named, in the item its tab shows. A
      # Hash of what was pointed at, or Refused (why).
      def run(caller, quote: nil, first_line: nil, last_line: nil, page: nil, label: nil)
        raise Refused, 'this reply cannot point at the work screen' unless caller

        board = Board.existing(caller.chat_id) or raise Refused, 'nothing is shown in the work screen'
        item = Look.target(board, caller).item
        file = item['file']
        point = case file && file['preview']
                when 'text' then text_point(board, item, quote, first_line, last_line)
                when 'pdf' then pdf_point(board, item, quote, page)
                else raise Refused, 'only lines of a text file or text of a PDF can be pointed at'
                end
        label = label_of(label)
        point['label'] = label if label
        Shown.add(caller.request_id, item, point: point)
        tell(caller, item, point)
        { item: item, point: point }
      rescue Look::Refused => e
        raise Refused, e.message
      end

      # The lines of the text, by their numbers or where the quote is.
      def text_point(board, item, quote, first_line, last_line)
        preview = Monadic::Workspace::SharedFolderPreview
        text = preview.text_view(read(board, item))[:text]
        count = preview.text_lines(text).size
        if quote
          found = match(text, quote) or raise Refused, 'the quote is not in the file; quote its text as it is'
          first = text[0...found.begin(0)].count("\n") + 1
          return { 'lines' => [first, first + found[0].count("\n")] }
        end
        unless first_line.is_a?(Integer) && first_line.between?(1, count)
          raise Refused, "give first_line (1 to #{count}) or a quote"
        end

        last = last_line.is_a?(Integer) ? last_line : first_line
        raise Refused, "last_line must be from #{first_line} to #{count}" unless last.between?(first_line, count)

        { 'lines' => [first_line, last] }
      end

      # The page of the PDF the quote is on (page, when given, is looked at
      # first), with the quote as found there.
      def pdf_point(board, item, quote, page)
        raise Refused, 'give a quote of the PDF\'s text' unless quote

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
        got = PdfText.extract(read(board, item), first: 1, last: PDF_PAGES, deadline: deadline - Shell::STOP_TIMEOUT)
        pages = got.pages.sort_by { |p| page.is_a?(Integer) && p[:page] == page ? 0 : 1 }
        pages.each do |p|
          found = match(p[:text], quote)
          return { 'page' => p[:page], 'quote' => found[0].gsub(/[[:space:]]+/, ' ')[0, QUOTE_CHARS] } if found
        end
        raise Refused, "the quote is not in the PDF's text (its first #{PDF_PAGES} pages); quote its text as it is"
      rescue PdfText::Unavailable => e
        raise Refused, "the PDF's text could not be read (#{e.reason})"
      end

      # Where quote is in text, each run of space in it matching any run of
      # space: a MatchData, or nil.
      def match(text, quote)
        words = quote.to_s.strip.split(/[[:space:]]+/)
        raise Refused, 'the quote is empty' if words.empty?
        raise Refused, "the quote is longer than #{QUOTE_CHARS} characters" if quote.length > QUOTE_CHARS

        text.match(Regexp.new(words.map { |w| Regexp.escape(w) }.join('[[:space:]]+')))
      end

      def read(board, item)
        board.file_read(item['id'], sha256: item.dig('file', 'sha256'))[:bytes]
      rescue Board::Refused, Artifact::NotAllowed, Artifact::Changed, FileItem::Busy => e
        raise Refused, "the item could not be read (#{e.message})"
      end

      # The label shown beside the mark: one line, at most LABEL_CHARS
      # characters, or nil.
      def label_of(label)
        text = label.to_s.gsub(/[[:cntrl:]]/, ' ').gsub(/[[:space:]]+/, ' ').strip
        text.empty? ? nil : text[0, LABEL_CHARS]
      end

      def tell(caller, item, point)
        return unless transport

        message = JSON.generate(type: 'workbench_point', item_id: item['id'], version: item.dig('file', 'sha256'),
                                point: point)
        transport.call(caller.tab, caller.generation, caller.chat_id, message)
      rescue StandardError
        nil
      end
    end
  end
end
