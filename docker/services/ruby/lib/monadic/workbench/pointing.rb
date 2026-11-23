# frozen_string_literal: true

require_relative 'board'

module Monadic
  module Workbench
    # What the user points at on the work screen with a message (a picture
    # with a mark, Picture; text they selected, Selection) is of the item
    # their tab has selected on the board, at the version the board has.
    module Pointing
      PAGES_LIMIT = 100_000
      # The shapes and colors a mark is drawn in (the page's palette, by
      # name: the model is told the name).
      SHAPES = %w[rect ellipse].freeze
      COLORS = %w[orange magenta cyan green yellow].freeze

      class Refused < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      module_function

      # The board's item the tab has selected, when it is the PDF data names
      # (item_id) at the version it names; Refused otherwise.
      def selected_pdf!(data, chat_id:, tab:, generation:)
        raise Refused, 'not_a_picture' unless data.is_a?(Hash)

        board = Board.existing(chat_id) or raise Refused, 'no_board'
        seen = board.observe(tab: tab.to_s, generation: generation) or raise Refused, 'not_this_tab'
        item = seen[:items].find { |i| i[:id] == seen[:selected] }
        raise Refused, 'not_selected' unless item && item[:id] == data['item_id']
        raise Refused, 'not_a_pdf' unless item[:kind] == 'file' && item[:preview].to_s == 'pdf'
        raise Refused, 'changed' unless data['version'] == item[:version]

        item
      end

      # The page and the pages data names, as [page, pages]; Refused when they
      # are not whole numbers in range.
      def page_of!(data)
        pages = whole(data['pages'], PAGES_LIMIT) or raise Refused, 'bad_page'
        page = whole(data['page'], pages) or raise Refused, 'bad_page'
        [page, pages]
      end

      # { shape, color, x, y, w, h } within the picture (fractions), or nil.
      # A mark with no color is orange.
      def mark_of(value)
        return nil unless value.is_a?(Hash) && SHAPES.include?(value['shape'])

        color = value.fetch('color', 'orange')
        return nil unless COLORS.include?(color)

        x, y, w, h = %w[x y w h].map { |k| value[k] }
        return nil unless [x, y, w, h].all? { |v| v.is_a?(Numeric) && v.to_f.finite? }
        return nil unless x >= 0 && y >= 0 && w.positive? && h.positive? && x + w <= 1.0001 && y + h <= 1.0001

        { 'shape' => value['shape'], 'color' => color, 'x' => x.to_f, 'y' => y.to_f, 'w' => w.to_f, 'h' => h.to_f }
      end

      # An Integer from 1 to limit, or nil.
      def whole(value, limit)
        value.is_a?(Integer) && value.between?(1, limit) ? value : nil
      end
    end
  end
end
