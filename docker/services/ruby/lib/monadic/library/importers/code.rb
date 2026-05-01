# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # Source code file importer.
      #
      # Reads a single code file and produces a monadic-conversation v1
      # hash where each top-level definition (function / class / module /
      # struct / impl …) becomes its own message under a single 'document'
      # narrator. The result is that retrieval via the Library treats each
      # definition as an independent chunk, which is the right granularity
      # for "find the function that does X" queries.
      #
      # Programming language is stored in conversation_metadata.topics
      # (e.g., topics: ["python"]) — the schema's `language` field is
      # reserved for ISO 639-1 human language codes.
      #
      # Caller-supplied options:
      #   :filename, :language (ISO 639-1, defaults to 'en'),
      #   :programming_language (overrides extension-based inference),
      #   :license (default 'private'), :title, :external_id, :topics,
      #   :speaker_id ('document'), :speaker_role ('narrator')
      #
      # tree-sitter-based exact parsing is deferred to Phase 2; the regex
      # boundary heuristics here are deliberately conservative and only
      # match top-level (column-0) declarations.
      module Code
        module_function

        DEFAULT_SPEAKER_ID = 'document'
        DEFAULT_SPEAKER_ROLE = 'narrator'
        DEFAULT_CONTENT_TYPE = 'code'
        DEFAULT_LICENSE = 'private'

        # Map common file extensions to a language slug. The slug is what
        # we record in topics and use to pick a boundary pattern.
        EXTENSION_LANGUAGE = {
          'rb' => 'ruby', 'rake' => 'ruby', 'gemspec' => 'ruby',
          'py' => 'python', 'pyw' => 'python',
          'js' => 'javascript', 'mjs' => 'javascript', 'cjs' => 'javascript', 'jsx' => 'javascript',
          'ts' => 'typescript', 'tsx' => 'typescript',
          'go' => 'go',
          'java' => 'java',
          'kt' => 'kotlin', 'kts' => 'kotlin',
          'swift' => 'swift',
          'rs' => 'rust',
          'c' => 'c', 'h' => 'c',
          'cpp' => 'cpp', 'cc' => 'cpp', 'cxx' => 'cpp', 'hpp' => 'cpp', 'hxx' => 'cpp',
          'cs' => 'csharp',
          'php' => 'php',
          'sh' => 'shell', 'bash' => 'shell', 'zsh' => 'shell',
          'sql' => 'sql',
          'pl' => 'perl', 'pm' => 'perl',
          'lua' => 'lua',
          'ex' => 'elixir', 'exs' => 'elixir',
          'scala' => 'scala',
          'clj' => 'clojure', 'cljs' => 'clojure',
          'hs' => 'haskell',
          'ml' => 'ocaml', 'mli' => 'ocaml',
          'r' => 'r',
          'jl' => 'julia'
        }.freeze

        # Top-level declaration patterns. Each regex matches lines that
        # start at column 0 and open a new "section" (definition, class,
        # struct, etc.). Languages without an entry fall back to paragraph
        # splitting; that still produces useful turns for short files.
        BOUNDARY_PATTERNS = {
          'ruby' => /\A(def|class|module)\s+\S/,
          'python' => /\A(?:async\s+)?(def|class)\s+\S/,
          'javascript' => /\A(?:export\s+(?:default\s+)?)?(?:async\s+)?(?:function|class)\s+\S|\A(?:export\s+)?(?:const|let|var)\s+\w+\s*=\s*(?:async\s*)?(?:\(|function)/,
          'typescript' => /\A(?:export\s+(?:default\s+)?)?(?:async\s+)?(?:function|class|interface|type|enum|namespace)\s+\S|\A(?:export\s+)?(?:const|let|var)\s+\w+\s*[:=]/,
          'go' => /\A(func|type|var|const)\s+\S/,
          'java' => /\A\s*(?:public|private|protected)?\s*(?:static\s+)?(?:final\s+)?(?:abstract\s+)?(?:class|interface|enum|record)\s+\S/,
          'kotlin' => /\A(?:public|private|protected|internal)?\s*(?:open\s+|sealed\s+|abstract\s+|data\s+)*(?:fun|class|interface|object|enum)\s+\S/,
          'swift' => /\A(?:public|private|internal|fileprivate|open)?\s*(?:final\s+)?(?:func|class|struct|enum|protocol|extension|actor)\s+\S/,
          'rust' => /\A(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?(?:fn|struct|enum|trait|impl|mod|type|const|static)\s+\S/,
          'csharp' => /\A\s*(?:public|private|protected|internal)?\s*(?:static\s+|abstract\s+|sealed\s+|partial\s+)*(?:class|interface|enum|struct|record|namespace)\s+\S/,
          'php' => /\A(?:abstract\s+|final\s+)?(?:function|class|interface|trait|namespace)\s+\S/,
          'scala' => /\A(?:abstract\s+|sealed\s+|case\s+|final\s+)*(?:def|class|object|trait|type|val|var)\s+\S/,
          'elixir' => /\A\s*(?:def|defp|defmodule|defmacro|defprotocol|defimpl|defstruct)\s+\S/
        }.freeze

        MIN_BLOCK_LEN = 200
        MAX_BLOCK_LEN = 4_000

        def can_import?(input)
          return false unless input.is_a?(String) && !input.strip.empty?
          # Conservative: detect at least one common code-boundary pattern
          # somewhere in the body. Used only when the importer is ever
          # invoked through dispatch; the WebSocket handler dispatches by
          # extension and bypasses this.
          BOUNDARY_PATTERNS.values.any? { |re| input.lines.any? { |line| line.match?(re) } }
        rescue StandardError
          false
        end

        def import(input, options = {})
          raise ArgumentError, 'Code import requires a String input' unless input.is_a?(String)

          filename = options[:filename] || options['filename']
          programming_language = options[:programming_language] || options['programming_language'] ||
                                 detect_language(filename)
          pattern = BOUNDARY_PATTERNS[programming_language]

          sections = pattern ? split_by_pattern(input, pattern) : []
          sections = paragraph_fallback(input) if sections.empty?
          raise ArgumentError, 'Code import produced no sections' if sections.empty?

          speaker_id = options[:speaker_id] || options['speaker_id'] || DEFAULT_SPEAKER_ID
          speaker_role = options[:speaker_role] || options['speaker_role'] || DEFAULT_SPEAKER_ROLE

          messages = sections.each_with_index.map do |section, idx|
            { 'id' => Base.message_id(idx),
              'speaker' => { 'id' => speaker_id },
              'text' => section }
          end

          participant = { 'id' => speaker_id, 'role' => speaker_role, 'description' => 'code_file' }
          label = options[:title] || options['title'] || filename
          participant['label'] = label.to_s unless label.to_s.strip.empty?

          metadata_options = options.dup
          metadata_options[:license] ||= metadata_options['license'] || DEFAULT_LICENSE
          metadata_options[:content_type] ||= metadata_options['content_type'] || DEFAULT_CONTENT_TYPE
          metadata_options[:title] ||= metadata_options['title'] || Base.derive_title_from_filename(filename)

          # Promote programming language into topics (the schema's
          # `language` field is reserved for ISO 639-1 human language).
          topics = Array(metadata_options[:topics] || metadata_options['topics']).map(&:to_s)
          topics << programming_language if programming_language && !topics.include?(programming_language)
          metadata_options[:topics] = topics unless topics.empty?

          source = options[:source] || options['source'] || build_source(filename)

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || options['conversation_id'] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: source, options: metadata_options),
            'participants' => [participant],
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        def detect_language(filename)
          return nil if filename.to_s.strip.empty?
          ext = File.extname(filename.to_s).sub(/\A\./, '').downcase
          # Files like "Rakefile" / "Gemfile" with no extension: fall back
          # to a basename match so heuristics still work.
          return EXTENSION_LANGUAGE[ext] if EXTENSION_LANGUAGE.key?(ext)
          base = File.basename(filename.to_s).downcase
          return 'ruby' if %w[rakefile gemfile guardfile capfile].include?(base)
          return 'shell' if base == '.bashrc' || base == '.zshrc' || base == '.bash_profile'
          nil
        end

        def build_source(filename)
          return 'code' if filename.to_s.strip.empty?
          "code:#{File.basename(filename.to_s)}"
        end

        # Split input into sections at lines matching `pattern`. Content
        # before the first boundary (shebang / imports / module-level
        # constants) is preserved as the first section so nothing is lost.
        def split_by_pattern(input, pattern)
          return [] if input.strip.empty?
          sections = []
          current = +''
          input.each_line do |line|
            if line.match?(pattern)
              sections << current.strip unless current.strip.empty?
              current = line.dup
            else
              current << line
            end
          end
          sections << current.strip unless current.strip.empty?
          sections.flat_map { |s| split_oversized(s) }
        end

        def paragraph_fallback(input)
          return [] if input.strip.empty?
          blocks = input.strip.split(/\r?\n\r?\n+/)
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

        # Hard cap turn size by splitting at blank lines when a section
        # exceeds MAX_BLOCK_LEN. A single 4000+ char function is split
        # mid-body — embedding quality outranks fence preservation here.
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
