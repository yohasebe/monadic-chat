# frozen_string_literal: true

require_relative '../utils/tool_image_utils'

module Monadic
  module Workbench
    # What an image made for the workbench must be before it becomes a
    # candidate: PNG, JPEG or WebP by its leading bytes, no larger than
    # MAX_BYTES, with a width and height read from its header within
    # MAX_SIDE and MAX_PIXELS. The header is read, not the whole image:
    # the page that shows it is what decodes it.
    module ImageCheck
      MAX_BYTES = 25 * 1024 * 1024
      MAX_SIDE = 8192
      MAX_PIXELS = 40_000_000
      # The base64 text sent for an image, at most (as for the shared
      # folder's tool images, ToolImageUtils).
      MAX_BASE64 = 5 * 1024 * 1024
      TYPES = %w[image/png image/jpeg image/webp].freeze

      class Refused < StandardError; end

      module_function

      # { content_type:, width:, height: } for bytes, or raises Refused.
      def check!(bytes)
        bytes = bytes.to_s.b
        raise Refused, 'empty image' if bytes.empty?
        raise Refused, 'image too large' if bytes.bytesize > MAX_BYTES

        type = Monadic::Utils::ToolImageUtils.image_media_type(bytes)
        raise Refused, 'not a PNG, JPEG or WebP image' unless TYPES.include?(type)

        width, height = dimensions(type, bytes)
        raise Refused, 'image size could not be read' unless width&.positive? && height&.positive?
        raise Refused, 'image too large' if width > MAX_SIDE || height > MAX_SIDE || width * height > MAX_PIXELS

        { content_type: type, width: width, height: height }
      end

      def dimensions(type, bytes)
        case type
        when 'image/png' then png(bytes)
        when 'image/jpeg' then jpeg(bytes)
        when 'image/webp' then webp(bytes)
        end
      end

      # The IHDR chunk comes first.
      def png(bytes)
        return nil unless bytes.byteslice(12, 4) == 'IHDR'.b

        bytes.byteslice(16, 8)&.unpack('NN')
      end

      # The first start-of-frame marker holds the size.
      def jpeg(bytes)
        at = 2
        while at + 4 <= bytes.bytesize
          return nil unless bytes.getbyte(at) == 0xFF

          marker = bytes.getbyte(at + 1)
          if marker == 0xFF
            at += 1
            next
          end
          length = bytes.byteslice(at + 2, 2).unpack1('n')
          return nil if length.nil? || length < 2

          if (0xC0..0xCF).cover?(marker) && ![0xC4, 0xC8, 0xCC].include?(marker)
            height, width = bytes.byteslice(at + 5, 4)&.unpack('nn')
            return [width, height]
          end
          at += 2 + length
        end
        nil
      end

      # VP8 (lossy), VP8L (lossless) or VP8X (extended) chunk.
      def webp(bytes)
        chunk = bytes.byteslice(12, 4)
        case chunk
        when 'VP8 '.b
          return nil unless bytes.byteslice(23, 3) == "\x9D\x01\x2A".b

          w, h = bytes.byteslice(26, 4).unpack('vv')
          [w & 0x3FFF, h & 0x3FFF]
        when 'VP8L'.b
          return nil unless bytes.getbyte(20) == 0x2F

          b = bytes.byteslice(21, 4).unpack('C4')
          [1 + (((b[1] & 0x3F) << 8) | b[0]), 1 + (((b[3] & 0x0F) << 10) | (b[2] << 2) | ((b[1] & 0xC0) >> 6))]
        when 'VP8X'.b
          w = bytes.byteslice(24, 3).unpack('C3')
          h = bytes.byteslice(27, 3).unpack('C3')
          [1 + (w[0] | (w[1] << 8) | (w[2] << 16)), 1 + (h[0] | (h[1] << 8) | (h[2] << 16))]
        end
      end
    end
  end
end
