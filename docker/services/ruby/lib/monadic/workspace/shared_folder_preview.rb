# frozen_string_literal: true

module Monadic
  module Workspace
    # Files of the shared folder as the Shared Folder panel previews them.
    # Read only. Which files can be previewed, and as what, comes from the
    # extension (TYPES), never from the content or from the request.
    #
    # A file is opened without following a link in its last part, and then
    # the system is asked where the open file really is: a folder on the
    # way that was swapped for a link after it was checked would lead out
    # of the shared folder, and the last part's check cannot see that. Where
    # the system cannot be asked, nothing is opened.
    module SharedFolderPreview
      class Invalid < StandardError; end
      class NotText < StandardError; end
      class Unavailable < StandardError; end
      class TooLarge < StandardError; end

      TEXT_LIMIT = 256 * 1024 # bytes of a text file shown
      CHUNK = 64 * 1024

      MEDIA = {
        'png' => %w[image image/png], 'jpg' => %w[image image/jpeg], 'jpeg' => %w[image image/jpeg],
        'gif' => %w[image image/gif], 'webp' => %w[image image/webp],
        'mp3' => %w[audio audio/mpeg], 'wav' => %w[audio audio/wav], 'm4a' => %w[audio audio/mp4],
        'ogg' => %w[audio audio/ogg], 'oga' => %w[audio audio/ogg], 'flac' => %w[audio audio/flac],
        'mp4' => %w[video video/mp4], 'm4v' => %w[video video/mp4], 'webm' => %w[video video/webm],
        'mov' => %w[video video/quicktime],
        'pdf' => %w[pdf application/pdf]
      }.freeze

      # Shown as text. The work screen can also draw some of them
      # (render_for); nothing here runs what a file holds.
      TEXT = %w[txt md markdown csv tsv json jsonl log yml yaml toml ini xml html htm svg mmd mermaid
                rb py js ts sh r tex bib srt vtt css sql].freeze

      # What the work screen draws a text file as, by its extension.
      RENDER = {
        'md' => 'markdown', 'markdown' => 'markdown', 'mmd' => 'diagram', 'mermaid' => 'diagram',
        'csv' => 'table', 'tsv' => 'table', 'svg' => 'svg', 'html' => 'html', 'htm' => 'html'
      }.freeze
      # Extensions of two parts, looked at before the last part alone.
      RENDER_COMPOUND = { '.vl.json' => 'vega_lite', '.vega-lite.json' => 'vega_lite' }.freeze
      # Bytes of a file the work screen draws: a larger one is shown as text.
      RENDER_LIMIT = 8 * 1024 * 1024

      F_GETPATH = 50 # fcntl(2) on macOS
      MAXPATHLEN = 1024

      module_function

      def extension(name)
        File.extname(name.to_s).delete_prefix('.').downcase
      end

      # What a text file is drawn as ("markdown", "diagram", "table", "svg",
      # "html", "vega_lite"), or nil when it is shown as text only.
      def render_for(name)
        base = File.basename(name.to_s).downcase
        RENDER_COMPOUND.each { |suffix, render| return render if base.end_with?(suffix) && base.size > suffix.size }
        return nil unless kind_for(base) == 'text'

        RENDER[extension(base)]
      end

      # "image", "audio", "video", "pdf", "text" or nil.
      def kind_for(name)
        ext = extension(name)
        return 'text' if TEXT.include?(ext)

        MEDIA.dig(ext, 0)
      end

      # The type a media file is sent as; nil for text and anything else.
      def mime_for(name)
        MEDIA.dig(extension(name), 1)
      end

      # Opens the file at relative (a path in the shared folder) for reading,
      # when its kind is one of kinds (any preview kind when nil). Returns
      # the open file, its stat and its kind; the caller closes the file.
      def open_file(relative, kinds: nil)
        root = SharedFolder.data_root
        parts = SharedFolder.parts_of(relative)
        raise Invalid, 'the shared folder itself is not a file' if parts.empty?

        kind = kind_for(parts.last)
        raise Invalid, 'the file cannot be previewed' unless kind && (kinds.nil? || kinds.include?(kind))

        # Each part as the folder spells it (a file system that ignores case
        # would reach another spelling), and no link on the way.
        dir = root
        parts.each do |part|
          raise Invalid, 'the file is not there' unless Dir.children(dir).include?(part)

          dir = File.join(dir, part)
        end
        SharedFolder.folder_at(root, parts[0..-2])
        path = File.join(root, *parts)
        raise Invalid, 'the entry is not a file' unless File.lstat(path).file?

        # NONBLOCK: an entry that became a FIFO does not hold the open.
        io = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
        begin
          stat = io.stat
          raise Invalid, 'the entry is not a file' unless stat.file?
          # As bytes: the system's answer carries no encoding, and a name
          # outside ASCII would never equal the UTF-8 path otherwise.
          raise Invalid, 'the file is not where it was checked' unless opened_path(io).b == path.b

          io.binmode
        rescue StandardError
          io.close
          raise
        end
        [io, stat, kind]
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
        raise Invalid, 'the file is not there'
      rescue SharedFolder::Invalid => e
        raise Invalid, e.message
      end

      # Where the system says the open file is.
      def opened_path(io)
        proc_fd = "/proc/self/fd/#{io.fileno}"
        return File.readlink(proc_fd) if File.symlink?(proc_fd)

        if RUBY_PLATFORM.include?('darwin')
          buffer = "\0" * MAXPATHLEN
          io.fcntl(F_GETPATH, buffer)
          return buffer.unpack1('Z*')
        end
        raise Unavailable, 'this system cannot tell where an open file is'
      end

      # The first TEXT_LIMIT bytes of a text file, as text_view shows them.
      # NotText when what is shown holds a NUL byte.
      def read_text(relative)
        io, stat, = open_file(relative, kinds: %w[text])
        begin
          data = io.read(TEXT_LIMIT + 1) || +''
        ensure
          io.close
        end
        text_view(data).merge(file_bytes: stat.size)
      end

      # Text as it is shown, from the bytes of a file: the first limit bytes
      # (a UTF-8 character the limit cut short is left out), as UTF-8 (bytes
      # that are not UTF-8 become U+FFFD), without a leading byte order
      # mark, with every line end as "\n". NotText when the bytes shown hold
      # a NUL byte. The file's version (its sha256) is of the raw bytes, not
      # of this text. Returns { text:, truncated:, shown_bytes: } (the bytes
      # of the file the text comes from).
      def text_view(bytes, limit: TEXT_LIMIT)
        truncated = bytes.bytesize > limit
        data = (truncated ? bytes.byteslice(0, limit) : bytes).b
        raise NotText, 'the file is not text' if data.include?("\0")

        data = drop_cut_character(data) if truncated
        text = data.dup.force_encoding('UTF-8').scrub("\uFFFD").delete_prefix("\uFEFF").gsub(/\r\n?/, "\n")
        { text: text, truncated: truncated, shown_bytes: data.bytesize }
      end

      # The whole of a file the work screen draws, as text: the bytes must
      # be UTF-8 (a leading byte order mark is left out) without a NUL, at
      # most RENDER_LIMIT; line ends become "\n". NotText otherwise; a
      # larger file is TooLarge. Nothing is cut: what is drawn is the whole.
      def render_text(bytes)
        raise TooLarge, 'the file is too large to draw' if bytes.bytesize > RENDER_LIMIT

        text = bytes.b.delete_prefix("\xEF\xBB\xBF".b).force_encoding('UTF-8')
        raise NotText, 'the file is not text' if !text.valid_encoding? || text.include?("\0")

        text.gsub(/\r\n?/, "\n")
      end

      # The lines of a text_view text, numbered from 1 by their place: no
      # line in empty text; a "\n" ends the line before it, so a final "\n"
      # adds no line. The page makes its lines the same way (workbench.js).
      def text_lines(text)
        return [] if text.empty?

        body = text.end_with?("\n") ? text[0...-1] : text
        body.empty? ? [''] : body.split("\n", -1)
      end

      # Leaves out a UTF-8 character the limit cut short at the end.
      def drop_cut_character(data)
        bytes = data.bytes
        (1..[3, bytes.size].min).each do |back|
          byte = bytes[-back]
          next if byte & 0xC0 == 0x80 # a continuation byte: look further back

          needed = if byte >= 0xF0 then 4
                   elsif byte >= 0xE0 then 3
                   elsif byte >= 0xC0 then 2
                   else 1
                   end
          return needed > back ? data.byteslice(0, data.bytesize - back) : data
        end
        data
      end

      RANGE_HEADER_LIMIT = 200

      # What a Range header asks of a file of size bytes:
      #   nil            no Range, or one not taken up (another unit, several
      #                  ranges, or not valid): the whole file is sent
      #   :unsatisfiable nothing of the file is in the range (416)
      #   [first, last]  the bytes to send (206)
      def range_for(header, size)
        return nil if header.nil? || header.empty? || header.bytesize > RANGE_HEADER_LIMIT

        match = header.strip.match(/\Abytes=([^,]+)\z/)
        return nil unless match

        spec = match[1].strip
        if (m = spec.match(/\A(\d{1,19})-(\d{0,19})\z/))
          first = m[1].to_i
          last = m[2].empty? ? nil : m[2].to_i
          return nil if last && last < first
          return :unsatisfiable if first >= size

          [first, [last || (size - 1), size - 1].min]
        elsif (m = spec.match(/\A-(\d{1,19})\z/))
          length = m[1].to_i
          return :unsatisfiable if length.zero? || size.zero?

          [[size - length, 0].max, size - 1]
        end
      end

      # A response body that reads length bytes from offset of an open file
      # and closes it when the server is done (finished, cut off or HEAD).
      class FileBody
        def initialize(io, offset, length)
          @io = io
          @offset = offset
          @length = length
        end

        def each
          @io.seek(@offset)
          left = @length
          while left.positive?
            chunk = @io.read([CHUNK, left].min)
            break if chunk.nil? || chunk.empty? # the file got shorter

            left -= chunk.bytesize
            yield chunk
          end
        ensure
          close # also when the server does not
        end

        def close
          @io.close unless @io.closed?
        end
      end
    end
  end
end
