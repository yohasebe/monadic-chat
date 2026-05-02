# frozen_string_literal: true

require 'json'
require_relative 'base'

module Monadic
  module Library
    module Importers
      # PDF file importer.
      #
      # Two-stage pipeline:
      #   1. Python container extracts text + metadata via
      #      `library_pdf_extractor.py` (currently pdfplumber-based;
      #      will route through the dedicated extractor_service
      #      container for layout-aware extraction in a later phase).
      #   2. This module turns the extracted markdown into a v1
      #      monadic-conversation, splitting on heading boundaries when
      #      present and falling back to paragraph blocks otherwise.
      #
      # The two stages are decoupled so unit specs exercise stage 2 with a
      # canned markdown blob — no Docker required. The runtime caller (the
      # Library WebSocket handler) is responsible for stage 1.
      #
      # Caller-supplied options for `import`:
      #   :filename, :title, :author, :page_count, :license (default
      #   'private'), :language (ISO 639-1, defaults to 'en'),
      #   :external_id, :topics, :speaker_id ('document'),
      #   :speaker_role ('narrator')
      module Pdf
        module_function

        DEFAULT_SPEAKER_ID = 'document'
        DEFAULT_SPEAKER_ROLE = 'narrator'
        DEFAULT_CONTENT_TYPE = 'pdf'
        DEFAULT_LICENSE = 'private'

        # Heading regex: same H1..H3 rule as Markdown. The current
        # pdfplumber backend rarely emits ATX headings; this regex still
        # works whenever the source PDF was already markdown-like, and
        # the paragraph fallback covers the common case until Docling
        # restores layout-aware heading detection.
        SECTION_HEADING_RE = /\A#{Regexp.escape('#')}{1,3}\s+\S/.freeze

        MIN_BLOCK_LEN = 200
        MAX_BLOCK_LEN = 4_000

        # File-based importers are dispatched by extension; this is here
        # so dispatch can still recognise raw markdown extracted from a
        # PDF if someone hands it back.
        def can_import?(input)
          return false unless input.is_a?(String) && !input.strip.empty?
          input.lines.any? { |line| line.match?(SECTION_HEADING_RE) } || input.length > 500
        rescue StandardError
          false
        end

        # Stage 2 entry point. `content` is the markdown emitted by
        # `library_pdf_extractor.py`. Stage 1 belongs to the WebSocket
        # handler so unit specs stay Docker-free.
        def import(content, options = {})
          raise ArgumentError, 'PDF import requires a String content' unless content.is_a?(String)

          sections = split_sections(content)
          sections = paragraph_fallback(content) if sections.empty?
          raise ArgumentError, 'PDF import produced no sections' if sections.empty?

          speaker_id = options[:speaker_id] || options['speaker_id'] || DEFAULT_SPEAKER_ID
          speaker_role = options[:speaker_role] || options['speaker_role'] || DEFAULT_SPEAKER_ROLE
          filename = options[:filename] || options['filename']
          author = options[:author] || options['author']

          messages = sections.each_with_index.map do |section, idx|
            { 'id' => Base.message_id(idx),
              'speaker' => { 'id' => speaker_id },
              'text' => section }
          end

          participant = { 'id' => speaker_id, 'role' => speaker_role, 'description' => 'pdf_document' }
          label = options[:title] || options['title'] || author || filename
          participant['label'] = label.to_s unless label.to_s.strip.empty?

          metadata_options = options.dup
          metadata_options[:license] ||= metadata_options['license'] || DEFAULT_LICENSE
          metadata_options[:content_type] ||= metadata_options['content_type'] || DEFAULT_CONTENT_TYPE
          # Promote PDF metadata title into conversation_metadata when
          # the caller hasn't supplied a more specific one.
          if metadata_options[:title].to_s.strip.empty? && options[:title]
            metadata_options[:title] = options[:title]
          end
          # Final fallback: filename basename without extension. PDFs
          # without document-properties title still get a sensible label
          # in the Browse modal.
          metadata_options[:title] ||= Base.derive_title_from_filename(filename)

          source = options[:source] || options['source'] || build_source(filename)

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || options['conversation_id'] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: source, options: metadata_options),
            'participants' => [participant],
            'messages' => messages
          }
        end

        # Convenience: parse the JSON the Python extractor emits and call
        # `import` with the right options. Used by the WebSocket handler
        # in production; specs use it via stub data.
        def import_extraction_json(json_string, options = {})
          parsed = JSON.parse(json_string)
          merged = options.dup
          merged[:title] ||= parsed['title'] unless parsed['title'].to_s.strip.empty?
          merged[:author] ||= parsed['author'] unless parsed['author'].to_s.strip.empty?
          merged[:page_count] ||= parsed['page_count']
          import(parsed.fetch('markdown', ''), merged)
        end

        # ─── Internals ─────────────────────────────────────────────────

        def build_source(filename)
          return 'pdf' if filename.to_s.strip.empty?
          "pdf:#{File.basename(filename.to_s)}"
        end

        def split_sections(body)
          return [] if body.strip.empty?
          sections = []
          current = +''
          body.each_line do |line|
            if line.match?(SECTION_HEADING_RE)
              sections << current.strip unless current.strip.empty?
              current = line.dup
            else
              current << line
            end
          end
          sections << current.strip unless current.strip.empty?
          sections.flat_map { |s| split_oversized(s) }
        end

        def paragraph_fallback(body)
          return [] if body.strip.empty?
          blocks = body.strip.split(/\r?\n\r?\n+/)
          merged = []
          buf = +''
          blocks.each do |block|
            if buf.length < MIN_BLOCK_LEN
              buf << "\n\n" unless buf.empty?
              buf << block
            else
              merged << buf.strip
              buf = +block.dup
            end
          end
          merged << buf.strip unless buf.strip.empty?
          merged.flat_map { |b| split_oversized(b) }
        end

        def split_oversized(text)
          return [text] if text.length <= MAX_BLOCK_LEN
          parts = []
          remaining = text
          while remaining.length > MAX_BLOCK_LEN
            cut = remaining.rindex(/\r?\n\r?\n/, MAX_BLOCK_LEN) || MAX_BLOCK_LEN
            parts << remaining[0, cut].strip
            remaining = remaining[cut..].to_s.lstrip
          end
          parts << remaining.strip unless remaining.strip.empty?
          parts
        end
      end
    end
  end
end
