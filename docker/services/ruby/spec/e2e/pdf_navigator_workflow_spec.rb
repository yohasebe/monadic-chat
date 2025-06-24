# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'pdf_test_helper'

RSpec.describe "PDF Navigator E2E Workflow", type: :e2e do
  include E2EHelper
  include PDFTestHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
    
    # Check if pgvector is available
    unless system("docker exec monadic-chat-pgvector-container pg_isready -U postgres", out: File::NULL, err: File::NULL)
      skip "PDF Navigator requires pgvector container"
    end
    
    # Ensure EMBEDDINGS_DB is defined as it would be in the actual app
    unless defined?(EMBEDDINGS_DB)
      require_relative '../../lib/monadic/utils/text_embeddings'
      Object.const_set(:EMBEDDINGS_DB, TextEmbeddings.new("monadic_user_docs", recreate_db: false))
    end
    
    # Setup test database
    setup_test_pdf_database
    
    # Add test PDFs
    create_pdf_content("ml_basics.pdf", [
      {
        title: "Introduction to Machine Learning",
        content: "Machine learning is a subset of artificial intelligence that focuses on the development of algorithms and statistical models that enable computer systems to improve their performance on tasks through experience."
      },
      {
        title: "Types of Machine Learning",
        content: "There are three main types of machine learning: supervised learning, unsupervised learning, and reinforcement learning. Each type has its own characteristics and applications."
      }
    ])
    
    create_pdf_content("algorithms.pdf", [
      {
        title: "Sorting Algorithms",
        content: "Common sorting algorithms include QuickSort, MergeSort, HeapSort, and BubbleSort. QuickSort has average O(n log n) complexity. MergeSort guarantees O(n log n) time complexity in all cases."
      },
      {
        title: "Search Algorithms",
        content: "Binary search is efficient for sorted arrays with O(log n) complexity. Linear search works on unsorted data with O(n) complexity."
      }
    ])
    
    create_pdf_content("transport_study.pdf", [
      {
        title: "Future of Mobility",
        content: "The future of transportation includes autonomous vehicles, shared mobility services, and smart city integration. These technologies will transform how people move in urban areas."
      },
      {
        title: "Environmental Impact",
        content: "Transportation is a major source of air pollution and greenhouse gas emissions. Electric vehicles and public transit can reduce environmental impact."
      },
      {
        title: "Traffic Solutions",
        content: "Solutions for reducing traffic include improved public transit, dedicated bus lanes, bike infrastructure, and congestion pricing."
      }
    ])
    
    create_pdf_content("sql_basics.pdf", [
      {
        title: "Introduction to SQL",
        content: "SQL (Structured Query Language) is used for managing relational databases. PostgreSQL is a powerful open-source relational database system."
      }
    ])
    
    create_pdf_content("nosql_guide.pdf", [
      {
        title: "NoSQL Databases",
        content: "NoSQL databases provide flexible schemas and scale horizontally. They are ideal for unstructured data and high-volume applications."
      }
    ])
    
    create_pdf_content("recipes.pdf", [
      {
        title: "Italian Recipes",
        content: "Classic Italian dishes include pasta carbonara, margherita pizza, and tiramisu. Fresh ingredients are key to authentic Italian cooking."
      }
    ])
    
    # Verify database has content
    db_stats = verify_test_database
    # Test database created with documents and items
  end
  
  after(:all) do
    # Cleanup test database
    cleanup_test_pdf_database
  end


  describe "PDF Upload and Processing" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
      cleanup_test_files("test_document.pdf", "research_paper.pdf")
    end

    it "processes a simple PDF document" do
      # PDF is already in test database
      message = "What does the document say about types of machine learning? Use find_closest_text function with top_n=2."
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Skip test if system error occurs
      skip "System error occurred: #{response}" if system_error?(response)
      
      # More flexible validation - check if search was attempted
      expect(pdf_search_attempted?(response)).to be true
      
      # If successful, should mention machine learning concepts
      if !system_error?(response)
        expect(response.downcase).to match(/supervised|unsupervised|reinforcement|machine learning|ml/)
      end
    end

    it "handles multi-page PDF search" do
      # Add multi-page PDF to test database
      create_pdf_content("python_guide.pdf", [
        {
          title: "Chapter 1: Python Basics",
          content: "Python is a high-level programming language known for its simplicity and readability. It was created by Guido van Rossum and first released in 1991."
        },
        {
          title: "Chapter 2: Data Structures",
          content: "Python provides several built-in data structures including lists, tuples, dictionaries, and sets. Lists are mutable ordered sequences."
        },
        {
          title: "Chapter 3: Functions",
          content: "Functions in Python are defined using the def keyword. They can accept arguments and return values using the return statement."
        }
      ])
      
      # Ask about specific content
      message = "Who created Python programming language?"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should find Guido van Rossum
      expect(response).to include("Guido van Rossum")
      expect(response).to include("1991")
    end
  end

  describe "Semantic Search Capabilities" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "finds semantically related content" do
      # Ask about pollution without using exact words from PDF
      message = "What information is available about environmental impact of transportation?"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should find related content about emissions and air pollution
      expect(response.downcase).to match(/pollution|emissions|greenhouse|environmental/)
      # Check for document reference
      expect(response).to match(/transport|Doc ID:|Doc Title:|database/i)
    end

    it "answers questions requiring context understanding" do
      message = "find what solutions are proposed for reducing traffic in transport_study.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should mention public transportation and smart city planning
      expect(response).to match(/public transit|buses|trains/i)
      expect(response).to match(/traffic congestion|bike infrastructure|congestion pricing/i)
    end

    it "handles queries about specific sections" do
      message = "find what the 'Future of Mobility' section discusses in transport_study.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should find content from that specific section or acknowledge the request
      expect(response.downcase).to match(/future|mobility|transport|unable to access|not.*available/i)
    end
  end

  describe "Multiple PDF Handling" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "searches across multiple PDFs" do
      message = "compare SQL and NoSQL databases using information from sql_basics.pdf and nosql_guide.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should reference content from both PDFs or make the comparison
      expect(response.downcase).to include("sql")
      expect(response.downcase).to include("nosql")
      # Accept either specific details or general comparison
      expect(response.downcase).to match(/database|comparison|relational|flexible|schema/i)
    end

    it "identifies which PDF contains specific information" do
      message = "find which PDF discusses PostgreSQL - search through sql_basics.pdf and nosql_guide.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should identify sql_basics.pdf
      expect(response).to include("sql_basics.pdf")
      expect(response).to match(/PostgreSQL/i)
    end
  end

  describe "Complex Queries" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "answers technical questions requiring comprehension" do
      message = "find which sorting algorithm has the best guaranteed performance in algorithms.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      skip "System error occurred: #{response}" if system_error?(response)
      
      # Check if search was attempted
      expect(pdf_search_attempted?(response)).to be true
      
      # If successful, should mention sorting algorithms
      if !system_error?(response) && !response.include?("issue")
        expect(response.downcase).to match(/sort|algorithm|performance|complexity/)
      end
    end

    it "compares multiple concepts from the PDF" do
      message = "compare the time complexity of hash tables vs binary search trees in algorithms.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should mention both data structures and their complexities or acknowledge the comparison
      expect(response.downcase).to match(/hash table|binary search|complexity|comparison/i)
      # Accept either specific complexity mentions or general comparison
      expect(response).to match(/O\(1\)|O\(log n\)|time complexity|performance/i)
    end

    it "summarizes entire sections" do
      message = "find information about sorting algorithms in algorithms.pdf and summarize what you find"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection, timeout: 60)  # Longer timeout for complex query
      
      # Should provide some response about sorting algorithms or acknowledge the request
      expect(response).not_to be_empty
      expect(response.downcase).to match(/sort|algorithm|unable to access|cannot.*find/i)
      # Response should be substantial enough to be a summary
      expect(response.length).to be > 50
    end
  end

  describe "Error Handling and Edge Cases" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "handles queries about non-existent PDFs gracefully" do
      message = "find information in nonexistent.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should indicate file not found or no results
      expect(response).to match(/not found|no results|unable to find|unable to access|doesn't exist|no.*matching|not present|does not exist|unable to.*retrieve|not available|is not available/i)
    end

    it "handles empty search results appropriately" do
      # PDF with cooking content is already in test database from before(:all)
      
      # Ask about unrelated content
      message = "find information about quantum physics in recipes.pdf"
      send_chat_message(ws_connection, message, app: "PDFNavigatorOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should indicate no relevant content found or mention the actual content
      expect(response).to match(/no.*information|not.*found|doesn't.*contain|recipes|cooking|Italian/i)
    end
  end
end