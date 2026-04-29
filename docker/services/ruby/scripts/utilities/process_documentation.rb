#!/usr/bin/env ruby
# frozen_string_literal: true

# Build-time help database generator. Reads docs/*.md (and optionally
# docs_dev/*.md when --include-internal is passed), chunks them, embeds
# each chunk via the embeddings_service container, and writes a JSON dump
# at docker/services/ruby/help_data/help_db.json.
#
# Runtime model: the Ruby image bakes in this dump. On first start, the
# Ruby app loads it into Qdrant collections via Monadic::Help::DumpLoader.
# Therefore this script does not need a running Qdrant container — only
# embeddings_service.

require 'fileutils'
require 'json'
require 'digest'
require 'time'

require 'dotenv'

# Load env so EMBEDDINGS_URL / EMBEDDINGS_DEV_PORT can be picked up.
config_path = File.expand_path('~/monadic/config/env')
Dotenv.load(config_path) if File.exist?(config_path)

require_relative '../../lib/monadic/embeddings'
require_relative '../../lib/monadic/vector_store/schema'

class ProcessDocumentation
  Schema = Monadic::VectorStore::Schema

  PROJECT_ROOT  = File.expand_path('../../../../..', __dir__)
  DOCS_PATH     = File.join(PROJECT_ROOT, 'docs')
  DOCS_DEV_PATH = File.join(PROJECT_ROOT, 'docs_dev')

  HELP_DATA_DIR  = File.expand_path('../../help_data', __dir__)
  DUMP_PATH      = File.join(HELP_DATA_DIR, 'help_db.json')
  EXPORT_ID_PATH = File.join(HELP_DATA_DIR, 'export_id.txt')

  CHUNK_SIZE   = ENV.fetch('HELP_CHUNK_SIZE',   '3000').to_i
  OVERLAP_SIZE = ENV.fetch('HELP_OVERLAP_SIZE', '500').to_i
  DUMP_VERSION = '1'
  EMBEDDING_MODEL_LABEL = 'intfloat/multilingual-e5-base'

  def initialize(embeddings: Monadic::Embeddings.default_client)
    @embeddings = embeddings
    @processed_files = 0
    @total_chunks = 0
    @docs_points = []
    @items_points = []
    @next_doc_id = 1
    @next_item_id = 1
  end

  def process_all_docs(include_internal: false)
    include_internal ||= (ENV['DEBUG_MODE'] == 'true')

    puts 'Starting documentation processing...'
    puts "Docs path:           #{DOCS_PATH}"
    puts "Include internal:    #{include_internal}"
    puts "Embeddings endpoint: #{Monadic::Embeddings::Endpoint.base_url}"
    puts "Dump output:         #{DUMP_PATH}"

    info = @embeddings.info
    actual_dim = info['dimension']
    if actual_dim != Schema::EMBEDDING_DIMENSION
      raise "Embeddings service reports dimension #{actual_dim}; schema expects #{Schema::EMBEDDING_DIMENSION}"
    end

    process_root_docs
    process_language_docs('en', DOCS_PATH, is_internal: false)

    if include_internal
      puts "\n=== Processing Internal Documentation ==="
      if Dir.exist?(DOCS_DEV_PATH)
        process_language_docs('en', DOCS_DEV_PATH, is_internal: true)
      else
        puts "Warning: Internal docs path does not exist: #{DOCS_DEV_PATH}"
      end
    end

    write_dump

    puts "\n=== Processing Complete ==="
    puts "Files processed:  #{@processed_files}"
    puts "Total chunks:     #{@total_chunks}"
    puts "Docs collection:  #{@docs_points.size} points"
    puts "Items collection: #{@items_points.size} points"
    puts "Dump written to:  #{DUMP_PATH}"
  end

  private

  # ─── Document discovery ────────────────────────────────────────────────

  def process_root_docs
    %w[README.md CHANGELOG.md].each do |name|
      path = File.join(PROJECT_ROOT, name)
      next unless File.exist?(path)
      puts "Processing root: #{name}"
      process_file_as_single_doc(path, name, name.sub('.md', ''), 'Overview')
    end
  end

  def process_language_docs(language, base_path, is_internal: false)
    return unless Dir.exist?(base_path)

    files = Dir.glob(File.join(base_path, '**/*.md'))
    files.reject! { |f| f.include?('/node_modules/') || f.include?('/_') }
    files.reject! { |f| f.include?('/ja/') || f.include?('/zh/') || f.include?('/ko/') } if language == 'en'

    files.each do |file_path|
      relative = file_path.sub(base_path + '/', '')
      next if relative.start_with?('_') || relative == 'index.md'
      process_markdown_file(file_path, relative, language, is_internal: is_internal)
    end
  end

  # ─── Per-file processing ───────────────────────────────────────────────

  def process_file_as_single_doc(file_path, relative_path, title, section)
    content = File.read(file_path, encoding: 'utf-8')
    chunks = create_chunks(content).reject { |c| c.strip.empty? }
    return if chunks.empty?

    items = chunks.each_with_index.map do |chunk, idx|
      {
        text: chunk,
        position: idx,
        heading: title,
        is_internal: false,
        metadata: { chunk_index: idx, file_path: relative_path, is_root_doc: true }
      }
    end

    doc_data = {
      title: title, file_path: relative_path, section: section, language: 'en',
      items: items.length, is_internal: false,
      metadata: {
        last_updated: File.mtime(file_path).to_s,
        content_hash: Digest::MD5.hexdigest(content),
        is_root_doc: true
      }
    }
    embed_and_store(doc_data, items)
    @processed_files += 1
    @total_chunks += items.length
  end

  def process_markdown_file(file_path, relative_path, language, is_internal: false)
    puts "Processing: #{relative_path} (#{language})#{is_internal ? ' (internal)' : ''}"
    content = File.read(file_path, encoding: 'utf-8')

    sections = parse_markdown_sections(content)
    items = []
    sections.each_with_index do |sec, sidx|
      chunks = create_chunks(sec[:content])
      chunks.each_with_index do |chunk, cidx|
        next if chunk.strip.empty?
        items << {
          text: chunk,
          position: items.length,
          heading: sec[:full_heading] || sec[:heading],
          is_internal: is_internal,
          metadata: {
            section_index: sidx,
            chunk_index: cidx,
            file_path: relative_path,
            heading_level: sec[:level],
            parent_heading: sec[:parent_heading]
          }
        }
      end
    end
    return if items.empty?

    doc_data = {
      title: extract_title_from_path(relative_path),
      file_path: relative_path,
      section: extract_section_from_path(relative_path),
      language: language,
      items: items.length,
      is_internal: is_internal,
      metadata: {
        last_updated: File.mtime(file_path).to_s,
        content_hash: Digest::MD5.hexdigest(content)
      }
    }
    embed_and_store(doc_data, items)
    @processed_files += 1
    @total_chunks += items.length
  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  # ─── Embedding + dump-shape conversion ─────────────────────────────────

  def embed_and_store(doc_data, items)
    item_texts = items.map { |i| i[:text] }
    puts "  Embedding #{item_texts.length} chunks..."
    item_vectors = @embeddings.embed_passages(item_texts)
    doc_vector = mean_vector(item_vectors)

    doc_id = @next_doc_id
    @next_doc_id += 1

    @docs_points << {
      'id' => doc_id,
      'vector' => { 'content' => doc_vector },
      'payload' => {
        'title' => doc_data[:title],
        'file_path' => doc_data[:file_path],
        'section' => doc_data[:section],
        'language' => doc_data[:language] || 'en',
        'items' => doc_data[:items] || 0,
        'is_internal' => doc_data[:is_internal] || false,
        'metadata' => doc_data[:metadata] || {}
      }
    }

    items.each_with_index do |item, idx|
      @items_points << {
        'id' => @next_item_id,
        'vector' => { 'content' => item_vectors[idx] },
        'payload' => {
          'doc_id' => doc_id,
          'text' => item[:text],
          'position' => item[:position],
          'heading' => item[:heading],
          'language' => doc_data[:language] || 'en',
          'is_internal' => item[:is_internal] || false,
          'metadata' => item[:metadata] || {}
        }
      }
      @next_item_id += 1
    end
  end

  def write_dump
    FileUtils.mkdir_p(HELP_DATA_DIR)

    dump = {
      'version' => DUMP_VERSION,
      'embedding_model' => EMBEDDING_MODEL_LABEL,
      'embedding_dimension' => Schema::EMBEDDING_DIMENSION,
      'exported_at' => Time.now.utc.iso8601,
      'collections' => {
        Schema::HELP_DOCS  => { 'points' => @docs_points },
        Schema::HELP_ITEMS => { 'points' => @items_points }
      }
    }

    File.write(DUMP_PATH, JSON.pretty_generate(dump))

    # Short fingerprint used by monadic.sh to invalidate the build cache
    # when the help DB content changes (so the embeddings image is rebuilt).
    export_id = Digest::SHA256.file(DUMP_PATH).hexdigest[0, 16]
    File.write(EXPORT_ID_PATH, export_id)
  end

  # ─── Markdown helpers (unchanged behaviour from the prior PG version) ──

  def parse_markdown_sections(content)
    sections = []
    current_section = { heading: 'Overview', content: '', parent_heading: nil }
    heading_stack = []

    content.lines.each do |line|
      if line =~ /^(\#{1,4})\s+(.+)$/
        sections << current_section if current_section[:content].strip.length.positive?

        heading_level = Regexp.last_match(1).length
        heading_text = Regexp.last_match(2).strip

        heading_stack = heading_stack.take(heading_level - 1)
        heading_stack << heading_text

        current_section = {
          heading: heading_text,
          full_heading: heading_stack.join(' > '),
          content: '',
          level: heading_level,
          parent_heading: heading_stack[-2]
        }
      else
        current_section[:content] += line
      end
    end

    sections << current_section if current_section[:content].strip.length.positive?
    sections
  end

  def create_chunks(text)
    text = text.strip.gsub(/\n{3,}/, "\n\n")
    return [text] if text.length <= CHUNK_SIZE

    chunks = []
    words = text.split(/\s+/)
    current_chunk = []
    current_size = 0

    words.each do |word|
      word_size = word.length + 1
      if current_size + word_size > CHUNK_SIZE && !current_chunk.empty?
        chunks << current_chunk.join(' ')

        overlap_words = []
        overlap_size = 0
        current_chunk.reverse_each do |w|
          break if overlap_size > OVERLAP_SIZE
          overlap_words.unshift(w)
          overlap_size += w.length + 1
        end

        current_chunk = overlap_words + [word]
        current_size = overlap_size + word_size
      else
        current_chunk << word
        current_size += word_size
      end
    end

    chunks << current_chunk.join(' ') unless current_chunk.empty?
    chunks
  end

  def extract_title_from_path(relative_path)
    parts = relative_path.split('/')
    filename = parts.last.sub(/\.md$/, '')
    title_parts = []
    if parts.length > 1
      title_parts << parts[-2].split(/[-_]/).map(&:capitalize).join(' ')
    end
    title_parts << filename.split(/[-_]/).map(&:capitalize).join(' ')
    title_parts.join(' - ')
  end

  def extract_section_from_path(relative_path)
    parts = relative_path.split('/')
    return 'General' if parts.length == 1
    parts[0].split(/[-_]/).map(&:capitalize).join(' ')
  end

  def mean_vector(vectors)
    return [] if vectors.empty?
    size = vectors.first.size
    sum = Array.new(size, 0.0)
    vectors.each { |v| v.each_with_index { |x, i| sum[i] += x.to_f } }
    sum.map { |x| x / vectors.size.to_f }
  end
end

if __FILE__ == $0
  include_internal = ARGV.include?('--include-internal')
  ProcessDocumentation.new.process_all_docs(include_internal: include_internal)
end
