# frozen_string_literal: true

require "spec_helper"
require "pg"

RSpec.describe "HelpEmbeddings", type: :integration do
  before(:all) do
    # Check if PostgreSQL is available
    begin
      @conn = PG.connect(
        host: ENV['POSTGRES_HOST'] || 'localhost',
        port: ENV['POSTGRES_PORT'] || '5433',
        user: ENV['POSTGRES_USER'] || 'postgres',
        password: ENV['POSTGRES_PASSWORD'] || 'postgres',
        dbname: 'monadic_help'
      )
    rescue PG::Error => e
      skip "PostgreSQL connection failed: #{e.message}"
    end
  end
  
  after(:all) do
    @conn&.close
  end
  
  describe "database structure" do
    it "has pgvector extension installed" do
      result = @conn.exec("SELECT * FROM pg_extension WHERE extname = 'vector'")
      expect(result.ntuples).to be > 0
    end
    
    it "uses text-embedding-3-large model (3072 dimensions)" do
      # Check if embedding column has correct dimensions in help_docs table
      result = @conn.exec(<<-SQL)
        SELECT column_name, data_type, udt_name
        FROM information_schema.columns
        WHERE table_name = 'help_docs' AND column_name = 'embedding'
      SQL
      
      if result.ntuples > 0
        # Get the vector dimension from the type modifier
        dim_result = @conn.exec(<<-SQL)
          SELECT atttypmod - 4 as dimensions
          FROM pg_attribute a
          JOIN pg_class c ON a.attrelid = c.oid
          WHERE c.relname = 'help_docs' AND a.attname = 'embedding'
        SQL
        
        if dim_result.ntuples > 0
          dimensions = dim_result[0]['dimensions'].to_i
          # pgvector stores dimension metadata with offset of 4
          # When we define vector(3072), pgvector stores it as 3068 + 4 = 3072
          # Expected dimension is 3068 in metadata, which represents 3072 actual dimensions
          expect(dimensions).to eq(3068)
        end
      else
        pending "help_docs table not found"
      end
    end
    
    it "has help_docs table with proper schema" do
      # Check help_docs table
      docs_result = @conn.exec(<<-SQL)
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = 'help_docs'
        ORDER BY ordinal_position
      SQL
      
      if docs_result.ntuples > 0
        columns = docs_result.map { |row| row['column_name'] }
        # Based on the actual schema
        expect(columns).to include('id', 'title', 'file_path', 'section', 'language', 'items', 'embedding')
      else
        pending "help_docs table not found"
      end
    end
    
    it "can perform vector similarity search without ivfflat indexes" do
      # Check if any data exists to search in help_docs
      count_result = @conn.exec("SELECT COUNT(*) FROM help_docs WHERE embedding IS NOT NULL")
      count = count_result[0]['count'].to_i
      
      if count > 0
        # Test a simple similarity search
        # Using a dummy vector of correct dimensions
        dummy_vector = "[" + Array.new(3072, "0.1").join(",") + "]"
        
        search_result = @conn.exec(<<-SQL)
          SELECT id, title, embedding <-> '#{dummy_vector}'::vector as distance
          FROM help_docs
          WHERE embedding IS NOT NULL
          ORDER BY distance
          LIMIT 5
        SQL
        
        expect(search_result.ntuples).to be > 0
        expect(search_result.ntuples).to be <= 5
      else
        pending "No embeddings data available for search test"
      end
    end
  end
end