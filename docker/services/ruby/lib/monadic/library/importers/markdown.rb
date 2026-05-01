# frozen_string_literal: true

require 'yaml'
require_relative 'base'

module Monadic
  module Library
    module Importers
      # Markdown file importer.
      #
      # Treats a Markdown document as a single-narrator "conversation" where
      # each top-level section becomes its own message. Heading boundaries
      # (ATX-style "# ", "## ", "### ") drive segmentation. When the input
      # has no headings, the body is split into paragraph blocks (separated
      # by blank lines) so very long files still land in turn-sized chunks
      # that are useful for retrieval.
      #
      # YAML frontmatter (--- ... --- at the top of the file) is parsed and
      # promoted into conversation_metadata when the keys match well-known
      # fields (title, language, topics, license, publication_date,
      # cite_as). Unknown frontmatter keys are silently dropped to keep the
      # validated metadata shape predictable.
      #
      # Caller-supplied options:
      #   :filename (String)  — surfaces in source / participant.label
      #   :title (String)     — overrides frontmatter / inferred title
      #   :language, :license, :topics, :publication_date, :cite_as,
      #   :external_id       — passed through to conversation_metadata
      #   :speaker_id        — defaults to "document"
      #   :speaker_role      — defaults to "narrator"
      module Markdown
        module_function

        DEFAULT_SPEAKER_ID = 'document'
        DEFAULT_SPEAKER_ROLE = 'narrator'
        DEFAULT_CONTENT_TYPE = 'markdown'
        DEFAULT_LICENSE = 'private'

        # ATX heading: 1-3 leading '#' followed by a space and the title.
        # We segment on H1..H3 so deep documents do not over-fragment.
        SECTION_HEADING_RE = /\A#{Regexp.escape('#')}{1,3}\s+\S/.freeze

        # Paragraph split fallback. Empty line separates blocks. Blocks
        # below MIN_BLOCK_LEN are merged forward so a stray "---" or short
        # line does not become its own turn.
        MIN_BLOCK_LEN = 200
        # Anything longer than this in a single block is split further on
        # paragraph boundaries until it fits, preventing one giant turn.
        MAX_BLOCK_LEN = 4_000

        # Optional probe — file-based importers are dispatched by extension
        # in the WebSocket handler, so this exists mainly so dispatch's
        # detect can tell a markdown blob from speaker-labelled plain text.
        def can_import?(input)
          return false unless input.is_a?(String) && !input.strip.empty?
          # A heading line, frontmatter fence, or fenced code block is a
          # strong markdown signal.
          input.lines.any? { |line| line.match?(SECTION_HEADING_RE) } ||
            input.start_with?("---\n") ||
            input.include?("\n```")
        rescue StandardError
          false
        end

        def import(input, options = {})
          raise ArgumentError, 'Markdown import requires a String input' unless input.is_a?(String)

          frontmatter, body = extract_frontmatter(input)
          merged_options = merge_frontmatter(frontmatter, options)

          sections = split_sections(body)
          sections = paragraph_fallback(body) if sections.empty?
          raise ArgumentError, 'Markdown import produced no sections' if sections.empty?

          speaker_id = merged_options[:speaker_id] || merged_options['speaker_id'] || DEFAULT_SPEAKER_ID
          speaker_role = merged_options[:speaker_role] || merged_options['speaker_role'] || DEFAULT_SPEAKER_ROLE
          filename = merged_options[:filename] || merged_options['filename']

          messages = sections.each_with_index.map do |section, idx|
            { 'id' => Base.message_id(idx),
              'speaker' => { 'id' => speaker_id },
              'text' => section }
          end

          participant = { 'id' => speaker_id, 'role' => speaker_role }
          label = merged_options[:title] || merged_options['title'] || filename
          participant['label'] = label.to_s unless label.to_s.strip.empty?
          participant['description'] = 'markdown_document'

          metadata_options = merged_options.dup
          metadata_options[:license] ||= metadata_options['license'] || DEFAULT_LICENSE
          metadata_options[:content_type] ||= metadata_options['content_type'] || DEFAULT_CONTENT_TYPE

          source = options[:source] || options['source'] || build_source(filename)

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => merged_options[:conversation_id] || merged_options['conversation_id'] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: source, options: metadata_options),
            'participants' => [participant],
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        def build_source(filename)
          return 'markdown' if filename.to_s.strip.empty?
          "markdown:#{File.basename(filename.to_s)}"
        end

        # Strip a leading YAML frontmatter block when present. Returns
        # [frontmatter_hash_or_nil, body_string].
        def extract_frontmatter(input)
          return [nil, input] unless input.start_with?("---\n") || input.start_with?("---\r\n")
          # Find the closing fence on a line of its own.
          rest = input.sub(/\A---\r?\n/, '')
          if (m = rest.match(/\A(.*?)\r?\n---\r?\n/m))
            yaml = m[1]
            body = rest[m.end(0)..] || ''
            begin
              parsed = YAML.safe_load(yaml, permitted_classes: [Date, Time])
              return [parsed.is_a?(Hash) ? parsed : nil, body]
            rescue StandardError
              return [nil, input]
            end
          end
          [nil, input]
        end

        # Promote known frontmatter keys into the importer options hash.
        # Unknown keys are dropped because conversation_metadata has a
        # closed shape; keeping random YAML keys would risk schema breaks.
        FRONTMATTER_PASSTHROUGH = %w[
          title language license topics cite_as external_id publication_date
        ].freeze

        def merge_frontmatter(frontmatter, options)
          merged = options.dup
          return merged unless frontmatter.is_a?(Hash)
          FRONTMATTER_PASSTHROUGH.each do |k|
            next if merged.key?(k.to_sym) || merged.key?(k)
            value = frontmatter[k]
            merged[k.to_sym] = value unless value.nil?
          end
          merged
        end

        # Split body on H1/H2/H3 ATX headings. The text preceding the first
        # heading (preamble) is kept as its own section when non-empty so
        # nothing is dropped silently.
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
          sections.empty? ? [] : sections.flat_map { |s| split_oversized(s) }
        end

        # Paragraph-block fallback for heading-less files. Blank-line
        # separated blocks; tiny blocks are merged with the next so a
        # single "***" rule doesn't become a turn.
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

        # Hard cap turn size by splitting on paragraph boundaries when a
        # single section exceeds MAX_BLOCK_LEN. Code blocks inside a long
        # section are not specially preserved here — embedding quality is
        # better with focused chunks even at the cost of cutting fences.
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
