# frozen_string_literal: true

module Monadic
  module Workspace
    # What each purpose accepts: an extension from its list and leading bytes
    # that match that kind of file. A renamed file of another kind is turned
    # away here, before any tool runs on it. Whether the file actually decodes
    # is a question for the tool that reads it.
    module FileTypes
      ISO_MEDIA = ->(head) { head.bytesize >= 12 && head.byteslice(4, 4) == 'ftyp' }
      EBML = ->(head) { head.start_with?("\x1A\x45\xDF\xA3".b) }
      AVI = ->(head) { head.start_with?('RIFF'.b) && head.byteslice(8, 4) == 'AVI '.b }

      PURPOSES = {
        'video' => {
          '.mp4' => ISO_MEDIA,
          '.m4v' => ISO_MEDIA,
          '.mov' => ISO_MEDIA,
          '.webm' => EBML,
          '.mkv' => EBML,
          '.avi' => AVI
        }.freeze
      }.freeze

      HEAD_BYTES = 16

      class Rejected < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      module_function

      def purposes
        PURPOSES.keys
      end

      def extensions(purpose)
        PURPOSES.fetch(purpose).keys
      end

      # Raises Rejected unless name and leading bytes fit the purpose.
      def check!(purpose, name, head)
        checks = PURPOSES[purpose] or raise Rejected.new(:purpose, 'This kind of attachment is not accepted.')
        # Not File.extname: it raises on a NUL byte, which a name from a form can hold.
        ext = name.to_s.b[/\.[A-Za-z0-9]{1,10}\z/].to_s.downcase
        matcher = checks[ext]
        unless matcher
          raise Rejected.new(:extension, "Files of this type cannot be attached here. Accepted: #{checks.keys.join(', ')}")
        end
        return if matcher.call(head.to_s.b)

        raise Rejected.new(:content, "The file's contents do not match its #{ext} extension.")
      end
    end
  end
end
