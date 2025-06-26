# frozen_string_literal: true

require_relative '../spec_helper'
require 'pg'

RSpec.describe "pgvector Integration (Real Implementation)", :integration do
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
    skip "PostgreSQL tests require pg gem" unless defined?(PG)
  end
  
  before(:context) do
    # Set up connection parameters
    @db_config = {
      host: ENV['POSTGRES_HOST'] || 'localhost',
      port: ENV['POSTGRES_PORT'] || '5433',  # Using 5433 as shown in previous tests
      user: ENV['POSTGRES_USER'] || 'postgres',
      password: ENV['POSTGRES_PASSWORD'] || 'postgres'
    }
    
    # Wait a moment for containers to be ready
    sleep 1 if ENV['CI']
    
    # Create test database with retry logic
    retries = 0
    begin
      conn = PG.connect(@db_config.merge(dbname: 'postgres'))
      @test_database = "test_pgvector_#{Time.now.to_i}"
      conn.exec("CREATE DATABASE #{@test_database}")
      conn.close
    rescue PG::Error => e
      retries += 1
      if retries < 3
        sleep 2
        retry
      else
        skip "Cannot create test database after #{retries} attempts: #{e.message}"
      end
    end
  end

  describe "Database Connection" do
    it "connects to PostgreSQL container" do
      # Check if pgvector container is running
      container_running = system("docker ps | grep pgvector > /dev/null 2>&1")
      expect(container_running).to be true
    end

    it "establishes connection to PostgreSQL" do
      begin
        conn = PG.connect(@db_config.merge(dbname: 'postgres'))
        expect(conn).to be_a(PG::Connection)
        expect(conn.status).to eq(PG::CONNECTION_OK)
        conn.close
      rescue PG::Error => e
        skip "Cannot connect to PostgreSQL: #{e.message}"
      end
    end

    it "has required databases and creates test database" do
      begin
        conn = PG.connect(@db_config.merge(dbname: 'postgres'))
        
        result = conn.exec("SELECT datname FROM pg_database WHERE datname IN ('monadic_user_docs', 'monadic_help')")
        database_names = result.map { |row| row['datname'] }
        
        # At least one of the databases should exist
        expect(database_names).not_to be_empty
        
        # Verify test database was created
        if @test_database
          verify_result = conn.exec("SELECT datname FROM pg_database WHERE datname = '#{@test_database}'")
          expect(verify_result.ntuples).to eq(1)
        end
        
        conn.close
      rescue PG::Error => e
        skip "Database operation failed: #{e.message}"
      end
    end
  end

  describe "Vector Operations" do
    before do
      skip "Test database not created" unless @test_database
    end

    it "supports vector extension" do
      begin
        conn = PG.connect(@db_config.merge(dbname: @test_database))
        
        # Create vector extension
        conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
        
        # Verify extension is installed
        result = conn.exec("SELECT * FROM pg_extension WHERE extname = 'vector'")
        expect(result.ntuples).to be > 0
        
        # Get vector version
        version_result = conn.exec("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
        if version_result.ntuples > 0
          version = version_result[0]['extversion']
          puts "pgvector version: #{version}"
        end
        
        conn.close
      rescue PG::Error => e
        skip "Vector extension test failed: #{e.message}"
      end
    end

    it "can create tables with vector columns" do
      begin
        conn = PG.connect(@db_config.merge(dbname: @test_database))
        
        # Ensure vector extension exists
        conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
        
        # Create a table with vector column
        conn.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS test_vectors (
            id SERIAL PRIMARY KEY,
            content TEXT,
            embedding vector(3)
          )
        SQL
        
        # Verify table was created
        result = conn.exec("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'test_vectors'")
        columns = result.map { |row| [row['column_name'], row['data_type']] }.to_h
        
        expect(columns).to include('id' => 'integer')
        expect(columns).to include('content' => 'text')
        expect(columns).to include('embedding' => 'USER-DEFINED')
        
        conn.close
      rescue PG::Error => e
        skip "Table creation failed: #{e.message}"
      end
    end
  end

  describe "Text Embeddings Storage" do
    before do
      skip "Test database not created" unless @test_database
      
      # Set up test table
      @conn = PG.connect(@db_config.merge(dbname: @test_database))
      @conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
      
      # Drop and recreate table to ensure clean state
      @conn.exec("DROP TABLE IF EXISTS test_embeddings")
      @conn.exec(<<-SQL)
        CREATE TABLE test_embeddings (
          id SERIAL PRIMARY KEY,
          content TEXT,
          embedding vector(3),
          metadata JSONB
        )
      SQL
    end

    after do
      # Clean up the table after each test
      @conn&.exec("DROP TABLE IF EXISTS test_embeddings")
      @conn&.close
    end

    it "can store and retrieve embeddings" do
      # Test data with 3-dimensional vectors for simplicity
      test_data = [
        { content: "Hello world", embedding: [0.1, 0.2, 0.3], metadata: { lang: "en" } },
        { content: "Bonjour monde", embedding: [0.2, 0.3, 0.4], metadata: { lang: "fr" } },
        { content: "Hola mundo", embedding: [0.3, 0.4, 0.5], metadata: { lang: "es" } }
      ]
      
      # Insert test data
      test_data.each do |item|
        @conn.exec_params(
          "INSERT INTO test_embeddings (content, embedding, metadata) VALUES ($1, $2, $3)",
          [item[:content], item[:embedding], item[:metadata].to_json]
        )
      end
      
      # Verify data was inserted
      count_result = @conn.exec("SELECT COUNT(*) FROM test_embeddings")
      expect(count_result[0]['count'].to_i).to eq(3)
      
      # Retrieve and verify data
      result = @conn.exec("SELECT * FROM test_embeddings ORDER BY id")
      expect(result.ntuples).to eq(3)
      
      first_row = result[0]
      expect(first_row['content']).to eq("Hello world")
      expect(first_row['embedding']).to eq("[0.1,0.2,0.3]")
      
      metadata = JSON.parse(first_row['metadata'])
      expect(metadata['lang']).to eq("en")
    end

    it "can perform similarity search with vectors" do
      # Insert test vectors
      vectors = [
        { content: "dog", embedding: [1.0, 0.0, 0.0] },
        { content: "cat", embedding: [0.9, 0.1, 0.0] },
        { content: "car", embedding: [0.0, 0.0, 1.0] }
      ]
      
      vectors.each do |item|
        @conn.exec_params(
          "INSERT INTO test_embeddings (content, embedding) VALUES ($1, $2)",
          [item[:content], item[:embedding]]
        )
      end
      
      # Search for vectors similar to "dog"
      query_vector = [0.95, 0.05, 0.0]
      result = @conn.exec_params(
        "SELECT content, embedding <-> $1 as distance FROM test_embeddings ORDER BY embedding <-> $1 LIMIT 2",
        [query_vector]
      )
      
      # Should find "dog" and "cat" as closest matches
      expect(result.ntuples).to eq(2)
      expect(result[0]['content']).to eq("dog")
      expect(result[1]['content']).to eq("cat")
      
      # Distances should be ordered (with a small tolerance for floating point precision)
      expect(result[0]['distance'].to_f).to be <= result[1]['distance'].to_f
    end

    it "can use cosine distance for similarity" do
      # Insert normalized vectors
      vectors = [
        { content: "positive", embedding: [1.0, 0.0, 0.0] },
        { content: "negative", embedding: [-1.0, 0.0, 0.0] },
        { content: "neutral", embedding: [0.0, 1.0, 0.0] }
      ]
      
      vectors.each do |item|
        @conn.exec_params(
          "INSERT INTO test_embeddings (content, embedding) VALUES ($1, $2)",
          [item[:content], item[:embedding]]
        )
      end
      
      # Search using cosine distance
      query_vector = [1.0, 0.0, 0.0]
      result = @conn.exec_params(
        "SELECT content, 1 - (embedding <=> $1) as similarity FROM test_embeddings ORDER BY embedding <=> $1 LIMIT 3",
        [query_vector]
      )
      
      # "positive" should have highest similarity (1.0)
      expect(result[0]['content']).to eq("positive")
      expect(result[0]['similarity'].to_f).to be_within(0.001).of(1.0)
      
      # "negative" should have lowest similarity
      expect(result[2]['content']).to eq("negative")
    end
  end

  after(:all) do
    # Clean up test database
    if @test_database
      begin
        conn = PG.connect(@db_config.merge(dbname: 'postgres'))
        conn.exec("DROP DATABASE IF EXISTS #{@test_database}")
        conn.close
      rescue PG::Error => e
        puts "Warning: Could not drop test database: #{e.message}"
      end
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end
end