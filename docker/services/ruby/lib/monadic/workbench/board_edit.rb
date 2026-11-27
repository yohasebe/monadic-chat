# frozen_string_literal: true

require 'json'
require_relative 'board'
require_relative 'capture'
require_relative 'look'
require_relative 'whiteboard'
require_relative 'whiteboard_background'
require_relative '../utils/privacy/outbound'

module Monadic
  module Workbench
    # What an edit of an image gets from a whiteboard drawn on it: the
    # picture under the board (the original, the copy the board keeps) and
    # the board as the asking tab draws it, at its saved version (the
    # reference: the picture with what was drawn on it). Only the board the
    # tab shows can give the reference; one that changed meanwhile gives
    # nothing, and no other image is used in its place. Calls no provider.
    module BoardEdit
      # One input of the edit: its role ('original' or 'reference'), its
      # bytes and type.
      Input = Struct.new(:role, :bytes, :content_type, keyword_init: true)

      class NoSource < StandardError; end

      # How often the tab is asked again when it was saving what was drawn
      # last (it answers for the version saved then).
      TRIES = 3

      module_function

      # Whether item (of the chat's work screen) is a whiteboard file.
      def whiteboard?(item)
        path = item&.dig('file', 'path')
        !path.nil? && Whiteboard.kept_as?(path)
      end

      # [original, reference] for the whiteboard item_id (nil: the one the
      # caller's tab shows), or NoSource (why).
      def inputs(workbench, item_id: nil)
        board = Board.existing(workbench.chat_id) or raise NoSource, 'there is no work screen'
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Look::DEADLINE
        TRIES.times do
          target = shown(board, workbench, item_id)
          item = target.item
          version = item.dig('file', 'sha256')
          data = parsed(board.file_read(item['id'], sha256: version, limit: Whiteboard::BYTES_LIMIT)[:bytes])
          background = Whiteboard.background_of(data) or raise NoSource, 'this whiteboard has no picture under it to edit'
          check_words!(workbench.session, data)
          original = WhiteboardBackground.read(item.dig('file', 'path'), background)
          reference = drawn(board, target, workbench, deadline, Whiteboard.frame_of(background))
          next if reference == :saving

          return [Input.new(role: 'original', bytes: original, content_type: background['content_type']),
                  Input.new(role: 'reference', bytes: reference.bytes, content_type: reference.content_type)]
        end
        raise NoSource, 'the whiteboard is still being saved; ask again in a moment'
      rescue Whiteboard::Refused, JSON::ParserError
        raise NoSource, 'the whiteboard could not be read'
      rescue WhiteboardBackground::Missing, WhiteboardBackground::Changed
        raise NoSource, 'the picture under the whiteboard is no longer the one it was drawn on'
      rescue Artifact::Changed, Artifact::Missing, Artifact::NotAllowed, Board::Refused, FileItem::Busy, FileItem::TooLarge
        raise NoSource, 'the whiteboard changed or could not be read'
      end

      # The board the caller's tab shows (Board::Target): the one named by
      # item_id must be it.
      def shown(board, workbench, item_id)
        target = board.look_target(tab: workbench.tab, generation: workbench.generation)
        unless target.is_a?(Board::Target) && whiteboard?(target.item) && (item_id.nil? || target.item['id'] == item_id.to_s)
          raise NoSource, 'open the whiteboard in the work screen, then ask again'
        end
        raise NoSource, Board::PUT_AWAY if target.item['place'] == 'stash'

        target
      end

      def parsed(bytes) = JSON.parse(bytes.to_s)

      # Every text of the board, checked for the words the chat hides: one
      # left keeps the whole edit back (the picture holds them all).
      def check_words!(session, data)
        outbound = Monadic::Utils::Privacy::Outbound
        outbound.chat_session!(session)
        words = outbound.terms_of(session)
        return if words.empty?

        texts = Array(data['shapes']).filter_map { |shape| shape['text'] if shape.is_a?(Hash) && shape['text'].is_a?(String) }
        raise NoSource, 'the whiteboard holds a word this chat hides' if texts.any? { |text| outbound.leaks_word?(text, words) }
      rescue Monadic::Utils::Privacy::Outbound::Refused
        raise NoSource, "the chat's words could not be checked"
      end

      # The board as the tab draws it (a Look::ImageValue of the sheet's
      # proportions), :saving when the tab was saving what was drawn last,
      # or NoSource.
      def drawn(board, target, workbench, deadline, frame)
        item = target.item
        still = lambda do
          Look.current?(workbench) &&
            board.still_selected?(tab: workbench.tab, generation: workbench.generation, item: item, serial: target.serial)
        end
        answer = Capture.request(tab: workbench.tab, generation: workbench.generation, chat_id: workbench.chat_id,
                                 request_id: workbench.request_id, item_id: item['id'], version: item.dig('file', 'sha256'),
                                 serial: target.serial, wants: ['image'], deadline: deadline, valid: still)
        image, note, = Look::Pdf.image_of(answer)
        return :saving if note == 'saving'
        raise NoSource, 'the whiteboard could not be drawn as it is now' unless image && same_shape?(image, frame)
        raise NoSource, 'the whiteboard changed while it was drawn' unless still.call

        image
      rescue Capture::Failed
        raise NoSource, 'the work screen did not answer; ask again in a moment'
      end

      # Whether image has the sheet's proportions (within 1%).
      def same_shape?(image, frame)
        (image.width * frame.height - image.height * frame.width).abs <= 0.01 * frame.width * image.height
      end
    end
  end
end
