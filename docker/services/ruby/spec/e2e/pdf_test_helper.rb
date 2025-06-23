# frozen_string_literal: true

require 'pg'
require 'tempfile'
require_relative '../../lib/monadic/utils/text_embeddings'

# Define EMBEDDINGS_DB if not already defined
# Don't create it here - let it be created after CONFIG is loaded

# Helper for PDF Navigator E2E tests
module PDFTestHelper
  TEST_DB_NAME = 'monadic_user_docs'  # Use the actual production database name
  
  # Setup test PDF database by clearing existing data
  def setup_test_pdf_database
    # Create EMBEDDINGS_DB instance if not already defined
    if defined?(EMBEDDINGS_DB)
      @test_embeddings = EMBEDDINGS_DB
    else
      # Create new instance - CONFIG should be loaded by now
      @test_embeddings = TextEmbeddings.new(TEST_DB_NAME)
      # Define the constant for other tests
      Object.const_set(:EMBEDDINGS_DB, @test_embeddings)
    end
    
    # Clear existing data for clean test environment
    begin
      conn = @test_embeddings.instance_variable_get(:@conn)
      if conn
        # Store original data count for restoration if needed
        result = conn.exec("SELECT COUNT(*) FROM docs")
        @original_doc_count = result[0]['count'].to_i
        
        # Clear all data
        conn.exec("DELETE FROM items")
        conn.exec("DELETE FROM docs")
        puts "Cleared existing data from database (was #{@original_doc_count} docs)"
      end
    rescue => e
      puts "WARNING: Could not clear database: #{e.message}"
    end
    
    @test_embeddings
  end
  
  # Add test PDF content to database
  def add_test_pdf(title, content_blocks)
    return unless @test_embeddings
    
    # Prepare document data
    doc_data = {
      title: title,
      items: content_blocks.size,
      metadata: {
        type: 'pdf',
        pages: content_blocks.size
      }
    }
    
    # Prepare items data - each block becomes a chunk
    items_data = content_blocks.map do |block|
      text = ""
      text += "#{block[:title]}\n\n" if block[:title]
      text += block[:content]
      
      {
        text: text,
        metadata: {
          tokens: text.split.size # Approximate token count
        }
      }
    end
    
    # Store embeddings using the same method as PDF upload
    api_key = CONFIG["OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]
    
    puts "DEBUG: Storing embeddings for #{title} with #{items_data.size} items" if ENV['E2E_DEBUG']
    
    begin
      result = @test_embeddings.store_embeddings(doc_data, items_data, api_key: api_key)
      puts "DEBUG: Successfully stored embeddings for #{title}" if ENV['E2E_DEBUG']
    rescue => e
      puts "ERROR storing embeddings: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
      raise e
    end
  end
  
  # Search in test database
  def search_test_pdf(query, limit: 5)
    return [] unless @test_embeddings
    @test_embeddings.search(query, limit: limit)
  end
  
  # Cleanup test database
  def cleanup_test_pdf_database
    if @test_embeddings
      begin
        conn = @test_embeddings.instance_variable_get(:@conn)
        if conn
          # Clear test data
          conn.exec("DELETE FROM items")
          conn.exec("DELETE FROM docs")
          puts "Cleaned up test data from database"
        end
      rescue => e
        puts "WARNING: Could not cleanup database: #{e.message}"
      end
    end
  end
  
  # Helper to create test PDF content
  def create_pdf_content(title, sections)
    content_blocks = sections.map do |section|
      {
        title: section[:title],
        content: section[:content]
      }
    end
    
    add_test_pdf(title, content_blocks)
  end
  
  # Verify test database has content
  def verify_test_database
    return unless @test_embeddings
    
    begin
      conn = @test_embeddings.instance_variable_get(:@conn)
      
      # Check docs table
      result = conn.exec("SELECT COUNT(*) FROM docs")
      doc_count = result[0]['count'].to_i
      puts "DEBUG: Test database has #{doc_count} documents" if ENV['E2E_DEBUG']
      
      # Check items table
      result = conn.exec("SELECT COUNT(*) FROM items")
      item_count = result[0]['count'].to_i
      puts "DEBUG: Test database has #{item_count} document items" if ENV['E2E_DEBUG']
      
      { docs: doc_count, items: item_count }
    rescue => e
      puts "ERROR verifying database: #{e.message}"
      { docs: 0, items: 0 }
    end
  end
end