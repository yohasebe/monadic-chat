# frozen_string_literal: true

require 'base64'
require_relative '../capture'
require_relative '../pdf_text'
require_relative '../../shell'

module Monadic
  module Workbench
    module Look
      # What a look gives of a PDF on the work screen, in parts kept apart:
      # for scope visible, the part of the page in view as the tab's page
      # drew it (an image cut from its canvas: what the page showed, not
      # checked against the PDF), the text of that whole page read from the
      # PDF's version on the server, and the text the user selected in it;
      # for scope whole, the text of its first WHOLE_PAGES pages. A part
      # that could not be had says why; a look that has none is refused.
      module Pdf
        WHOLE_PAGES = 100
        # Characters of the line that names each page in scope whole
        # ("--- page 100 ---" and its line ends), at most.
        PAGE_LINE_CHARS = 20
        SELECTION_CHARS = 8000
        # The image cut from the page, at most.
        IMAGE_SIDE = 2048
        IMAGE_PIXELS = 4_194_304
        IMAGE_NOTES = %w[not_in_view drawing redrawn failed too_large].freeze

        module_function

        # bytes: a lambda giving the PDF's bytes at the item's version.
        def visible(selection, caller, deadline, valid, bytes)
          item = selection.item
          answer = Capture.request(tab: caller.tab, generation: caller.generation, chat_id: caller.chat_id,
                                   request_id: caller.request_id, item_id: item['id'],
                                   version: item.dig('file', 'sha256'), serial: selection.serial,
                                   wants: %w[range image selection], deadline: deadline, valid: valid)
          page, pages = page_of(answer)
          selection_text, selection_cut = selection_of(answer)
          image, image_note, crop = image_of(answer)
          text, text_note, total, text_cut = page_text(bytes.call, page, deadline,
                                                       Look::TEXT_CHARS - selection_text.to_s.length)
          if total && total != pages
            raise Refused.new('changed', 'the PDF the tab shows is not the one on the work screen; open it again')
          end

          parts = { 'image' => image ? true : image_note, 'page_text' => text ? true : text_note,
                    'selection' => selection_text ? true : 'none' }
          unless image || text || selection_text
            raise Refused.new(text_note == 'pdf_text_unavailable' ? 'pdf_text_unavailable' : 'range_unknown',
                              'nothing of the page in view could be had')
          end

          cuts = [('page_text' if text_cut), ('selection' if selection_cut)].compact
          { image: image, text: text.to_s, selection: selection_text, selection_cut: selection_cut, parts: parts,
            pages: { first: page, last: page, total: pages }, crop: crop, cuts: cuts, truncated: cuts.any?,
            empty: text == '' }
        rescue Capture::Failed => e
          raise Refused.new(REASONS.include?(e.reason) ? e.reason : 'range_unknown', e.message)
        end

        # The text of the first WHOLE_PAGES pages of the PDF.
        def whole(bytes, deadline)
          got = PdfText.extract(bytes, first: 1, last: WHOLE_PAGES, deadline: deadline - Shell::STOP_TIMEOUT,
                                       chars: Look::TEXT_CHARS - (WHOLE_PAGES * PAGE_LINE_CHARS))
          given = got.pages
          text = given.map { |p| "--- page #{p[:page]} ---\n#{p[:text]}\n" }.join
          last = given.last && given.last[:page]
          cut = !got.stopped_at.nil? || given.any? { |p| p[:cut] } || got.total_pages > WHOLE_PAGES
          { text: text, parts: { 'page_text' => true }, pages: { first: 1, last: last, total: got.total_pages },
            cuts: cut ? ['page_text'] : [], truncated: cut, empty: given.all? { |p| p[:text].empty? },
            stopped: got.timed_out ? 'time' : nil }
        rescue PdfText::Unavailable => e
          raise Refused.new(REASONS.include?(e.reason) ? e.reason : 'pdf_text_unavailable', e.message)
        end

        # The page in view and the number of pages, as the tab says them.
        def page_of(answer)
          range = answer['range']
          if range.is_a?(Hash)
            page = range['page']
            pages = range['pages']
            return [page, pages] if page.is_a?(Integer) && pages.is_a?(Integer) && page.between?(1, pages)
          end
          note = answer['note']
          raise Refused.new('not_shown', 'the PDF is not shown in the tab; look with scope whole') if note == 'not_shown'
          raise Refused.new('drawing', 'the PDF is still being drawn; look again in a moment') if note == 'drawing'
          if %w[changing selection_changed].include?(note)
            raise Refused.new('selection_changed', 'the work screen shows something else now; nothing was looked at')
          end

          raise Refused.new('range_unknown', 'the page in view is not known; look with scope whole')
        end

        def selection_of(answer)
          text = answer['selection_text']
          return [nil, false] unless text.is_a?(String) && !text.empty?

          cut = answer['selection_cut'] == true || text.length > SELECTION_CHARS
          [text[0, SELECTION_CHARS], cut]
        end

        # The image the tab cut from its canvas, checked here, with the part
        # of the canvas it is; or nil and why.
        def image_of(answer)
          data = answer['image']
          note = IMAGE_NOTES.include?(answer['image_note']) ? answer['image_note'] : 'failed'
          return [nil, note, nil] unless data.is_a?(String) && !data.empty?
          return [nil, 'too_large', nil] if data.bytesize > Capture::IMAGE_LIMIT

          crop = crop_of(answer['crop'])
          image = ImageValue.checked(Base64.strict_decode64(data), source: 'workbench_capture')
          width = image.width
          height = image.height
          fits = width <= IMAGE_SIDE && height <= IMAGE_SIDE && width * height <= IMAGE_PIXELS
          return [nil, 'too_large', nil] unless fits
          return [nil, 'failed', nil] unless crop && crop['sent_width'] == width && crop['sent_height'] == height

          [image, nil, crop]
        rescue ArgumentError
          [nil, 'failed', nil]
        rescue Refused => e
          [nil, e.reason == 'too_large' ? 'too_large' : 'failed', nil]
        end

        def crop_of(crop)
          return nil unless crop.is_a?(Hash)

          keys = %w[x y width height sent_width sent_height]
          values = crop.slice(*keys)
          return nil unless values.size == keys.size && values.values.all? { |v| v.is_a?(Numeric) && v.finite? && v >= 0 }
          return nil unless values['width'].positive? && values['height'].positive?

          values.transform_values { |v| v.is_a?(Float) ? v.round(2) : v }
        end

        # The text of one page, at most chars characters: [text, nil,
        # total pages, whether it was cut] or [nil, why, nil, false].
        def page_text(bytes, page, deadline, chars)
          got = PdfText.extract(bytes, first: page, last: page, deadline: deadline - Shell::STOP_TIMEOUT,
                                       chars: [chars, Look::TEXT_CHARS].min)
          given = got.pages.first
          [given ? given[:text] : '', nil, got.total_pages, given ? given[:cut] : false]
        rescue PdfText::Unavailable => e
          [nil, e.reason == 'busy' ? 'busy' : 'pdf_text_unavailable', nil, false]
        end
      end
    end
  end
end
