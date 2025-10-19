#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "digest"
require "dotenv"

# Load environment module
require_relative '../../lib/monadic/utils/environment'

# Load configuration from ~/monadic/config/env
config_path = File.expand_path("~/monadic/config/env")
if File.exist?(config_path)
  Dotenv.load(config_path)
end

# Create CONFIG constant that TextEmbeddings expects
CONFIG = ENV.to_h

require_relative "../../lib/monadic/utils/help_embeddings"

# ProcessDocumentation handles the parsing and processing of Monadic Chat documentation
# for storage in the help embeddings database
class ProcessDocumentation
  # The docs directory is at the root of the monadic-chat project
  # Script is at: {project_root}/docker/services/ruby/scripts/utilities/
  # So we need to go up 5 levels to reach the project root
  DOCS_PATH = File.expand_path("../../../../../docs", __dir__)
  DOCS_DEV_PATH = File.expand_path("../../../../../docs_dev", __dir__)
  CHUNK_SIZE = ENV.fetch("HELP_CHUNK_SIZE", "3000").to_i # Larger chunks for better context
  OVERLAP_SIZE = ENV.fetch("HELP_OVERLAP_SIZE", "500").to_i # More overlap for continuity

  def initialize(recreate_db: false)
    @help_db = HelpEmbeddings.new(recreate_db: recreate_db)
    @processed_files = 0
    @total_chunks = 0
  end

  def process_all_docs(include_internal: false)
    # Auto-detect DEBUG_MODE if not explicitly specified
    include_internal ||= (ENV['DEBUG_MODE'] == 'true')

    puts "Starting documentation processing..."
    puts "Documentation path: #{DOCS_PATH}"
    puts "Does path exist? #{Dir.exist?(DOCS_PATH)}"
    puts "Include internal docs: #{include_internal}"
    puts "Current directory: #{Dir.pwd}"

    # Debug: List files in the expected directory
    if Dir.exist?(DOCS_PATH)
      puts "External docs found: #{Dir.glob(File.join(DOCS_PATH, '**/*.md')).count}"
    end

    # Process external documentation (always)
    process_language_docs("en", DOCS_PATH, is_internal: false)
    process_root_docs(is_internal: false)

    # Process internal documentation (only in DEBUG_MODE or when explicitly requested)
    if include_internal
      puts "\n=== Processing Internal Documentation ==="
      puts "Internal documentation path: #{DOCS_DEV_PATH}"
      if Dir.exist?(DOCS_DEV_PATH)
        puts "Internal docs found: #{Dir.glob(File.join(DOCS_DEV_PATH, '**/*.md')).count}"
        process_language_docs("en", DOCS_DEV_PATH, is_internal: true)
      else
        puts "Warning: Internal documentation path does not exist: #{DOCS_DEV_PATH}"
      end
    end

    # Display statistics
    stats = @help_db.get_stats
    puts "\n=== Processing Complete ==="
    puts "Files processed: #{@processed_files}"
    puts "Total chunks created: #{@total_chunks}"
    puts "Documents by language: #{stats[:documents_by_language]}"
    puts "Total items in database: #{stats[:total_items]}"
    puts "Average items per document: #{stats[:avg_items_per_doc]}"
  end

  private

  def process_root_docs(is_internal: false)
    # Project root is 5 levels up from this script
    project_root = File.expand_path("../../../../..", __dir__)

    doc_type = is_internal ? "internal root" : "root"
    puts "\nProcessing #{doc_type} documentation files..."

    # Process README.md
    readme_path = File.join(project_root, "README.md")
    if File.exist?(readme_path)
      puts "Processing: README.md (#{doc_type})"
      process_root_file(readme_path, "README", "Overview", is_internal: is_internal)
    end

    # Process CHANGELOG.md
    changelog_path = File.join(project_root, "CHANGELOG.md")
    if File.exist?(changelog_path)
      puts "Processing: CHANGELOG.md (#{doc_type})"
      process_root_file(changelog_path, "CHANGELOG", "Updates", is_internal: is_internal)
    end
  end
  
  def process_root_file(file_path, title, section, is_internal: false)
    content = File.read(file_path, encoding: "utf-8")

    # Calculate MD5 hash of content
    content_hash = Digest::MD5.hexdigest(content)
    relative_path = File.basename(file_path)

    # Check if document needs updating
    unless @help_db.document_needs_update?(relative_path, content_hash, "en")
      puts "  Skipping (unchanged): #{relative_path}"
      return
    end

    # Create chunks from content
    chunks = create_chunks(content)

    # Process chunks
    doc_items = []
    chunks.each_with_index do |chunk_text, chunk_idx|
      next if chunk_text.strip.empty?

      item = {
        text: chunk_text,
        position: doc_items.length,
        heading: title,
        is_internal: is_internal,
        metadata: {
          chunk_index: chunk_idx,
          file_path: relative_path,
          is_root_doc: true
        }
      }
      doc_items << item
    end

    # Skip if no content
    return if doc_items.empty?

    # Create document
    doc_data = {
      title: title,
      file_path: relative_path,
      section: section,
      language: "en",
      items: doc_items.length,
      is_internal: is_internal,
      metadata: {
        last_updated: File.mtime(file_path).to_s,
        original_path: file_path,
        content_hash: content_hash,
        is_root_doc: true
      }
    }

    # Store in database
    store_document(doc_data, doc_items)

    @processed_files += 1
    @total_chunks += doc_items.length
  rescue => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  def process_language_docs(language, base_path, is_internal: false)
    doc_type = is_internal ? "internal" : "external"
    puts "\nProcessing #{language} #{doc_type} documentation from #{base_path}..."

    # Find all markdown files
    markdown_files = Dir.glob(File.join(base_path, "**/*.md"))
    markdown_files.reject! { |f| f.include?("/node_modules/") || f.include?("/_") }

    # For English docs, exclude files in the /ja directory and any language-specific subdirectories
    if language == "en"
      markdown_files.reject! { |f| f.include?("/ja/") || f.include?("/zh/") || f.include?("/ko/") }
    end

    markdown_files.each do |file_path|
      process_markdown_file(file_path, language, base_path, is_internal: is_internal)
    end
  end

  def process_markdown_file(file_path, language, base_path, is_internal: false)
    relative_path = file_path.sub(base_path + "/", "")

    # Skip certain files
    return if relative_path.start_with?("_") || relative_path == "index.md"

    doc_type = is_internal ? "(internal)" : ""
    puts "Processing: #{relative_path} (#{language}) #{doc_type}"

    content = File.read(file_path, encoding: "utf-8")

    # Calculate MD5 hash of content
    content_hash = Digest::MD5.hexdigest(content)

    # Check if document needs updating
    unless @help_db.document_needs_update?(relative_path, content_hash, language)
      puts "  Skipping (unchanged): #{relative_path}"
      return
    end

    sections = parse_markdown_sections(content)

    # Determine document title and section from file path
    doc_title = extract_title_from_path(relative_path)
    doc_section = extract_section_from_path(relative_path)

    # Process each section
    doc_items = []
    sections.each_with_index do |section, idx|
      chunks = create_chunks(section[:content])

      chunks.each_with_index do |chunk_text, chunk_idx|
        next if chunk_text.strip.empty?

        item = {
          text: chunk_text,
          position: doc_items.length,
          heading: section[:full_heading] || section[:heading],
          is_internal: is_internal,
          metadata: {
            section_index: idx,
            chunk_index: chunk_idx,
            file_path: relative_path,
            heading_level: section[:level],
            parent_heading: section[:parent_heading]
          }
        }
        doc_items << item
      end
    end

    # Skip if no content
    return if doc_items.empty?

    # Create document embedding (average of all item embeddings will be computed by help_embeddings)
    doc_data = {
      title: doc_title,
      file_path: relative_path,
      section: doc_section,
      language: language,
      items: doc_items.length,
      is_internal: is_internal,
      metadata: {
        last_updated: File.mtime(file_path).to_s,
        original_path: file_path,
        content_hash: content_hash
      }
    }

    # Store in database
    store_document(doc_data, doc_items)

    @processed_files += 1
    @total_chunks += doc_items.length
  rescue => e
    puts "Error processing #{file_path}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  def parse_markdown_sections(content)
    sections = []
    current_section = { heading: "Overview", content: "", parent_heading: nil }
    heading_stack = [] # Track heading hierarchy
    
    content.lines.each do |line|
      # Check for headers (support up to h4 for better granularity)
      if line =~ /^(\#{1,4})\s+(.+)$/
        # Save previous section if it has content
        if current_section[:content].strip.length > 0
          sections << current_section
        end
        
        # Start new section
        heading_level = $1.length
        heading_text = $2.strip
        
        # Update heading stack
        heading_stack = heading_stack.take(heading_level - 1)
        heading_stack << heading_text
        
        # Create hierarchical heading
        full_heading = heading_stack.join(" > ")
        
        current_section = { 
          heading: heading_text,
          full_heading: full_heading,
          content: "",
          level: heading_level,
          parent_heading: heading_stack[-2]
        }
      else
        current_section[:content] += line
      end
    end
    
    # Don't forget the last section
    sections << current_section if current_section[:content].strip.length > 0
    
    sections
  end

  def create_chunks(text)
    # Remove excessive whitespace
    text = text.strip.gsub(/\n{3,}/, "\n\n")
    
    # If text is small enough, return as single chunk
    return [text] if text.length <= CHUNK_SIZE
    
    chunks = []
    words = text.split(/\s+/)
    current_chunk = []
    current_size = 0
    
    words.each do |word|
      word_size = word.length + 1 # +1 for space
      
      if current_size + word_size > CHUNK_SIZE && current_chunk.length > 0
        # Save current chunk
        chunks << current_chunk.join(" ")
        
        # Start new chunk with overlap
        overlap_words = []
        overlap_size = 0
        current_chunk.reverse.each do |w|
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
    
    # Add remaining chunk
    chunks << current_chunk.join(" ") if current_chunk.length > 0
    
    chunks
  end

  def extract_title_from_path(relative_path)
    # Extract meaningful title from file path
    parts = relative_path.split("/")
    filename = parts.last.sub(/\.md$/, "")
    
    # Convert filename to title case
    title_parts = []
    
    # Add directory context if not in root
    if parts.length > 1
      dir = parts[-2]
      title_parts << dir.split(/[-_]/).map(&:capitalize).join(" ")
    end
    
    # Add filename
    title_parts << filename.split(/[-_]/).map(&:capitalize).join(" ")
    
    title_parts.join(" - ")
  end

  def extract_section_from_path(relative_path)
    # Extract section from directory structure
    parts = relative_path.split("/")
    
    return "General" if parts.length == 1
    
    # Use the first directory as section
    parts[0].split(/[-_]/).map(&:capitalize).join(" ")
  end

  def store_document(doc_data, items)
    # First, get embeddings for all text chunks using batch processing
    doc_texts = items.map { |item| item[:text] }
    
    batch_size = (ENV['HELP_EMBEDDINGS_BATCH_SIZE'] || '50').to_i
    puts "Getting embeddings for #{doc_texts.length} text chunks (batch size: #{batch_size})..."
    
    begin
      doc_embeddings = @help_db.get_embeddings(doc_texts)
      puts "Got #{doc_embeddings.length} embeddings"
    rescue => e
      puts "Error getting embeddings: #{e.message}"
      raise
    end
    
    # Calculate average embedding for document
    avg_embedding = calculate_average_embedding(doc_embeddings)
    doc_data[:embedding] = avg_embedding
    
    # Insert document
    doc_id = @help_db.insert_doc(doc_data)
    
    # Insert items with their embeddings
    items.each_with_index do |item, idx|
      item[:doc_id] = doc_id
      item[:embedding] = doc_embeddings[idx]
      @help_db.insert_item(item)
    end
  end

  def calculate_average_embedding(embeddings)
    # Calculate the average of all embeddings
    return nil if embeddings.empty?
    
    dimension = embeddings.first.length
    avg = Array.new(dimension, 0.0)
    
    embeddings.each do |embedding|
      embedding.each_with_index do |val, idx|
        avg[idx] += val
      end
    end
    
    avg.map { |sum| sum / embeddings.length }
  end
end

# Run the script if called directly
if __FILE__ == $0
  # Parse command line arguments
  recreate = ARGV.include?("--recreate")
  include_internal = ARGV.include?("--include-internal")

  processor = ProcessDocumentation.new(recreate_db: recreate)
  processor.process_all_docs(include_internal: include_internal)
end