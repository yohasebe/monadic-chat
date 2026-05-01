# frozen_string_literal: true

require 'json'
require_relative 'base'

module Monadic
  module Library
    module Importers
      # Microsoft Office file importer (.docx / .xlsx / .pptx).
      #
      # Two-stage pipeline (mirrors PdfImporter):
      #   1. Python container extracts text + metadata via
      #      `library_office_extractor.py` (uses python-docx /
      #      openpyxl / python-pptx). The extractor normalises all three
      #      formats to a common markdown shape: section per
      #      paragraph-group / sheet / slide, with H1 markers where
      #      appropriate.
      #   2. This module turns the extracted markdown into a v1
      #      monadic-conversation, splitting on heading boundaries.
      #
      # The two stages are decoupled so unit specs feed canned markdown
      # — no Docker required.
      #
      # Caller-supplied options for `import`:
      #   :filename, :title, :author, :format ('docx'|'xlsx'|'pptx'),
      #   :license (default 'private'), :language (defaults to 'en'),
      #   :external_id, :topics, :speaker_id ('document'),
      #   :speaker_role ('narrator')
      module Office
        module_function

        DEFAULT_SPEAKER_ID = 'document'
        DEFAULT_SPEAKER_ROLE = 'narrator'
        DEFAULT_CONTENT_TYPE = 'document'
        DEFAULT_LICENSE = 'private'

        SECTION_HEADING_RE = /\A#{Regexp.escape('#')}{1,3}\s+\S/.freeze

        MIN_BLOCK_LEN = 200
        MAX_BLOCK_LEN = 4_000

        # Format slug → participant description, source prefix, and the
        # topic value we promote into conversation_metadata so library
        # search can narrow by sub-format.
        FORMAT_PROFILE = {
          'docx' => { description: 'office_document', source_prefix: 'office', topic: 'docx' },
          'xlsx' => { description: 'office_spreadsheet', source_prefix: 'office', topic: 'xlsx' },
          'pptx' => { description: 'office_presentation', source_prefix: 'office', topic: 'pptx' }
        }.freeze

        def can_import?(input)
          return false unless input.is_a?(String) && !input.strip.empty?
          input.lines.any? { |line| line.match?(SECTION_HEADING_RE) } || input.length > 200
        rescue StandardError
          false
        end

        def import(content, options = {})
          raise ArgumentError, 'Office import requires a String content' unless content.is_a?(String)

          format = (options[:format] || options['format']).to_s
          profile = FORMAT_PROFILE[format] || FORMAT_PROFILE['docx']

          sections = split_sections(content)
          sections = paragraph_fallback(content) if sections.empty?
          raise ArgumentError, 'Office import produced no sections' if sections.empty?

          speaker_id = options[:speaker_id] || options['speaker_id'] || DEFAULT_SPEAKER_ID
          speaker_role = options[:speaker_role] || options['speaker_role'] || DEFAULT_SPEAKER_ROLE
          filename = options[:filename] || options['filename']
          author = options[:author] || options['author']

          messages = sections.each_with_index.map do |section, idx|
            { 'id' => Base.message_id(idx),
              'speaker' => { 'id' => speaker_id },
              'text' => section }
          end

          participant = { 'id' => speaker_id, 'role' => speaker_role, 'description' => profile[:description] }
          label = options[:title] || options['title'] || author || filename
          participant['label'] = label.to_s unless label.to_s.strip.empty?

          metadata_options = options.dup
          metadata_options[:license] ||= metadata_options['license'] || DEFAULT_LICENSE
          metadata_options[:content_type] ||= metadata_options['content_type'] || DEFAULT_CONTENT_TYPE

          # Promote the format slug (docx / xlsx / pptx) into topics so
          # library_search can narrow by sub-format.
          topics = Array(metadata_options[:topics] || metadata_options['topics']).map(&:to_s)
          topics << profile[:topic] unless topics.include?(profile[:topic])
          metadata_options[:topics] = topics

          source = options[:source] || options['source'] || build_source(profile[:source_prefix], filename)

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || options['conversation_id'] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: source, options: metadata_options),
            'participants' => [participant],
            'messages' => messages
          }
        end

        # Convenience: parse the JSON the Python extractor emits and call
        # `import` with the right options. Used by the WebSocket handler.
        def import_extraction_json(json_string, options = {})
          parsed = JSON.parse(json_string)
          merged = options.dup
          merged[:title] ||= parsed['title'] unless parsed['title'].to_s.strip.empty?
          merged[:author] ||= parsed['author'] unless parsed['author'].to_s.strip.empty?
          merged[:format] ||= parsed['format'] unless parsed['format'].to_s.strip.empty?
          import(parsed.fetch('markdown', ''), merged)
        end

        # ─── Internals ─────────────────────────────────────────────────

        def build_source(prefix, filename)
          return prefix if filename.to_s.strip.empty?
          "#{prefix}:#{File.basename(filename.to_s)}"
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
