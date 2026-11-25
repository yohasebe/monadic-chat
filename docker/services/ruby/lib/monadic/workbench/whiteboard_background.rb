# frozen_string_literal: true

require 'digest'
require_relative 'artifact'
require_relative 'file_item'
require_relative 'image_check'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # The picture under a whiteboard drawn on an image: a copy of the image
    # as it was when the board was made, kept in the chat's whiteboards
    # folder as assets/<sha256>.<ext> (one copy for the chat's boards on the
    # same picture). A board keeps its record, never a path: the sha256,
    # the kind, the size in pixels and the EXIF orientation. The copy does
    # not follow the image's file, nor leave with its item.
    module WhiteboardBackground
      DIRNAME = 'assets'
      EXTENSIONS = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp' }.freeze
      SHA256 = /\A[0-9a-f]{64}\z/

      class Refused < StandardError; end

      module_function

      # The bytes of the image item item_id of board at version (the one
      # the user saw): an image made in the chat or an image file opened
      # from the shared folder. Refused for another kind or version.
      def bytes_of(board, item_id, version)
        item = board.item(item_id.to_s) or raise Refused, 'that item is not on the work screen now'
        if (entry = item['artifact'])
          read = Artifact.read(entry['id'], chat_id: board.chat_id)
          raise Refused, 'the image changed' unless read[:record][:sha256] == version.to_s

          read[:bytes]
        elsif item.dig('file', 'preview') == 'image'
          board.file_read(item['id'], sha256: version.to_s, limit: ImageCheck::MAX_BYTES)[:bytes]
        else
          raise Refused, 'only an image can be drawn on'
        end
      rescue Artifact::Changed
        raise Refused, 'the image changed'
      rescue Artifact::Error, FileItem::Refused, FileItem::TooLarge
        raise Refused, 'the image could not be read'
      rescue FileItem::Busy
        raise Refused, 'the work screen is reading other files now; try again in a moment'
      end

      # The record of an image (bytes), or Refused: a still PNG, JPEG or
      # WebP within ImageCheck's limits.
      def record_for(bytes)
        bytes = bytes.to_s.b
        info = ImageCheck.check!(bytes)
        raise Refused, 'a moving image cannot be drawn on' if ImageCheck.animated?(info[:content_type], bytes)

        { 'sha256' => Digest::SHA256.hexdigest(bytes), 'content_type' => info[:content_type],
          'pixel_width' => info[:width], 'pixel_height' => info[:height],
          'orientation' => ImageCheck.orientation(info[:content_type], bytes) }
      rescue ImageCheck::Refused => e
        raise Refused, e.message
      end

      # A record as a board keeps it (value: as read), or nil.
      def clean(value)
        return nil unless value.is_a?(Hash)

        sha256, type, width, height, turn = value.values_at('sha256', 'content_type', 'pixel_width', 'pixel_height',
                                                            'orientation')
        return nil unless sha256.is_a?(String) && sha256.match?(SHA256) && EXTENSIONS.key?(type)
        return nil unless [width, height].all? { |n| n.is_a?(Integer) && n.between?(1, ImageCheck::MAX_SIDE) }
        return nil unless turn.is_a?(Integer) && turn.between?(1, 8)

        { 'sha256' => sha256, 'content_type' => type, 'pixel_width' => width, 'pixel_height' => height,
          'orientation' => turn }
      end

      # The width and height of the sheet for record: the picture as it is
      # seen (turned by its orientation), its longer side long_side.
      def size_for(record, long_side)
        width, height = record.values_at('pixel_width', 'pixel_height')
        width, height = height, width if record['orientation'] >= 5
        scale = long_side.to_f / [width, height].max
        [(width * scale).round.clamp(1, long_side), (height * scale).round.clamp(1, long_side)]
      end

      # Writes the copy of bytes (record: theirs) in the whiteboards folder
      # dir (a real path), in place of what is at its name.
      def keep!(dir, bytes, record)
        assets = File.join(dir, DIRNAME)
        Monadic::Utils::SharedPathGuard.mkdir_p!(assets, strict: true)
        Monadic::Utils::SharedPathGuard.write_file!(File.join(assets, name_of(record)), bytes, mode: 'wb', replace: true,
                                                                                                strict: true)
      end

      def name_of(record) = "#{record['sha256']}.#{EXTENSIONS.fetch(record['content_type'])}"
    end
  end
end
