# frozen_string_literal: true

require_relative 'board'
require_relative 'file_item'
require_relative '../workspace/attachments'

module Monadic
  module Workbench
    # The file of an item of the work screen a tool reads as it is (a
    # video, an audio file, a MIDI file), named by the model with the item's
    # id: of a kind the tool takes, and still the version on the work
    # screen. A file the user put on the work screen is an attachment of the
    # chat and is given as its record (Attachments.resolve!, checked as
    # unchanged), for the tool's own way with attachments; a file opened
    # from the shared folder is given as its path there.
    module MediaItem
      # Why the item is not read (the message says it).
      class Refused < StandardError; end

      module_function

      # { record: } or { path: } of the item item_id on workbench's work
      # screen, when it is one of kinds ('video', 'audio', 'midi').
      def resolve(workbench, item_id, kinds:)
        raise Refused, 'there is no work screen for this reply' unless workbench

        board = Board.existing(workbench.chat_id)
        item = board&.item(item_id.to_s) or raise Refused, 'that item is not on the work screen now'
        raise Refused, Board::PUT_AWAY if item['place'] == 'stash'

        file = item['file'] or raise Refused, 'that item is not a file'
        raise Refused, "that item is not #{kinds.join(' or ')}" unless kinds.include?(kind_of(file))
        raise Refused, 'the file changed after it was put on the work screen; open it again' unless FileItem.same_version?(file)

        id = file['attachment_id']
        return { path: file['path'] } unless id

        record = Monadic::Workspace::Attachments.resolve!(chat_id: workbench.chat_id, attachment_id: id)
        raise Refused, 'the file changed after it was put on the work screen; open it again' unless record[:sha256] == file['sha256']

        { record: record }
      rescue Monadic::Workspace::Attachments::Unusable => e
        raise Refused, e.message
      end

      # 'video', 'audio' or 'midi': what a file item is, by what the work
      # screen made of it (a kind it plays, or the type of one it holds).
      def kind_of(file)
        return file['preview'] if %w[video audio].include?(file['preview'])

        type = file['content_type'].to_s
        return 'midi' if type == 'audio/midi'
        return 'video' if type.start_with?('video/')

        'audio' if type.start_with?('audio/')
      end
    end
  end
end
