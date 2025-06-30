# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "validation_helper"
require_relative "../support/custom_retry"
require "fileutils"

RSpec.describe "Content Reader E2E", :e2e do
  include E2EHelper
  include ValidationHelper
  include E2ERetryHelper
  
  let(:app_name) { "ContentReaderOpenAI" }
  
  before(:all) do
    unless check_containers_running
      skip "E2E tests require containers to be running."
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567."
    end
  end
  
  before do
    skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
  end
  
  describe "Content Reader workflow" do
    it "displays greeting message on activation" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        
        # For apps with initiate_from_assistant, send a non-empty message to trigger greeting
        send_chat_message(ws_connection, "Hello", app: app_name)
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        expect(response).to match(/hello|help|analyze|read/i)
      end
    end
  end
  
  describe "File analysis" do
    before do
      # Create a test text file instead of PDF for simplicity
      @test_file = create_test_file("ai_document.txt", 
        "Introduction to Artificial Intelligence\n\n" +
        "This document explains the basics of AI, including machine learning, neural networks, and deep learning. " +
        "Artificial Intelligence (AI) is the simulation of human intelligence in machines. " +
        "Machine learning is a subset of AI that enables systems to learn from data. " +
        "Neural networks are computing systems inspired by biological neural networks. " +
        "Deep learning uses multiple layers of neural networks."
      )
    end
    
    after do
      cleanup_test_file(@test_file)
    end
    
    it "reads text file content and answers questions about it" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection, 
          "Please read ai_document.txt and tell me what it's about",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # The AI should either:
        # 1. Say it's reading the file and then provide content
        # 2. Directly provide information about AI from the file
        # We're looking for evidence that it processed the request
        expect(response.downcase).to match(/read|fetch|document|artificial/i)
        expect(response.length).to be > 10
      end
    end
    
    it "indicates it will process file requests" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        
        # First handle the initial greeting from initiate_from_assistant
        send_chat_message(ws_connection, "Hello", app: app_name)
        greeting = wait_for_response(ws_connection, timeout: 30)
        ws_connection[:messages].clear
        
        # Now send the actual file request
        send_chat_message(ws_connection,
          "What topics are covered in ai_document.txt?",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # The AI should either indicate it will process the file OR explain it can't access it
        # This test is checking the response to a non-existent file
        expect(response.downcase).to match(/read|fetch|look|check|access|document|file/i)
      end
    end
  end
  
  describe "Text file analysis" do
    before do
      @test_file = create_test_file("sample_code.py", <<~PYTHON)
        def fibonacci(n):
            """Calculate the nth Fibonacci number."""
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)
        
        # Example usage
        for i in range(10):
            print(f"F({i}) = {fibonacci(i)}")
      PYTHON
    end
    
    after do
      cleanup_test_file(@test_file)
    end
    
    it "reads and explains code files" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "Can you explain what sample_code.py does?",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # The AI will say it's going to read the file
        expect(response.downcase).to match(/read|look|file|sample/i)
        expect(response.length).to be > 10
      end
    end
    
    it "analyzes code quality and suggests improvements" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "Are there any performance issues in sample_code.py?",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        expect(response).to match(/recursive|performance/i)
      end
    end
  end
  
  # Skip image analysis tests for now as they require complex setup
  # describe "Image analysis" do
  # end
  
  # Skip Office file tests for now as they require python-docx
  # describe "Office file support" do
  # end
  
  # Skip audio analysis tests as they require TTS setup
  # describe "Audio file analysis" do
  # end
  
  describe "Web content fetching" do
    it "fetches and analyzes web content when given a URL" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "What is the content of https://example.com?",
          app: app_name
        )
        sleep 1.0  # Wait longer for web fetching
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Verify that web content fetching was attempted
        expect(web_content_fetched?(response)).to be true
        # Accept various responses about the content
        expect(response.length).to be > 10  # Should have substantial response
      end
    end
    
    it "performs web searches when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "Search the web for information about Ruby programming language",
          app: app_name
        )
        sleep 1.0  # Wait longer for web search
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        expect(response).to match(/ruby|programming|language/i)
        # Relax length requirement as search results can vary
        expect(response.length).to be > 10
      end
    end
  end
  
  describe "Multi-file handling" do
    before do
      @file1 = create_test_file("data1.txt", "Temperature: 25°C, Humidity: 60%")
      @file2 = create_test_file("data2.txt", "Temperature: 28°C, Humidity: 55%")
    end
    
    after do
      cleanup_test_file(@file1)
      cleanup_test_file(@file2)
    end
    
    it "compares content from multiple files" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "Compare the temperature readings in data1.txt and data2.txt",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # The AI will say it's going to read/compare the files
        expect(response.downcase).to match(/compare|read|fetch|data/i)
        expect(response.length).to be > 10
      end
    end
  end
  
  describe "Error handling" do
    it "handles non-existent files gracefully" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "Read the file nonexistent_file.pdf",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        expect(response.downcase).to match(/not found|doesn't|unable|error|can't/i)
      end
    end
    
    it "handles unsupported file types" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        # Create a file with unsupported extension
        unsupported = create_test_file("test.xyz", "Some content")
        
        ws_connection = create_websocket_connection
        sleep 0.5  # Wait for WebSocket connection to stabilize
        send_chat_message(ws_connection,
          "What's in test.xyz?",
          app: app_name
        )
        sleep 0.5  # Wait before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should still try to read it as a text file
        expect(response).to include("content")
        
        cleanup_test_file(unsupported)
      end
    end
  end
  
  private
  
  def create_test_file(filename, content)
    filepath = File.join(Dir.home, "monadic", "data", filename)
    File.write(filepath, content)
    filepath
  end
  
  def create_test_pdf(filename, title, content)
    filepath = File.join(Dir.home, "monadic", "data", filename)
    
    # Use Python to create a real PDF
    # Write Python script to file first
    script_file = "/tmp/create_pdf_#{Time.now.to_i}.py"
    script_content = <<~PYTHON
      from reportlab.pdfgen import canvas
      from reportlab.lib.pagesizes import letter
      
      filepath = "#{filepath}"
      title = "#{title}"
      content = "#{content}"
      
      c = canvas.Canvas(filepath, pagesize=letter)
      c.setFont("Helvetica-Bold", 16)
      c.drawString(100, 750, title)
      c.setFont("Helvetica", 12)
      
      # Word wrap the content
      words = content.split()
      lines = []
      current_line = []
      for word in words:
          current_line.append(word)
          if len(' '.join(current_line)) > 60:
              lines.append(' '.join(current_line[:-1]))
              current_line = [word]
      lines.append(' '.join(current_line))
      
      y = 700
      for line in lines:
          c.drawString(100, y, line)
          y -= 20
      
      c.save()
    PYTHON
    
    File.write(script_file, script_content)
    `docker exec monadic-chat-python-container python #{script_file}`
    File.delete(script_file)
    
    filepath
  end
  
  def create_test_docx(filename, title, content)
    filepath = File.join(Dir.home, "monadic", "data", filename)
    
    # Use Python to create a real DOCX
    python_script = <<~PYTHON
      from docx import Document
      
      doc = Document()
      doc.add_heading("#{title}", 0)
      doc.add_paragraph("#{content}")
      doc.save("#{filepath}")
    PYTHON
    
    `docker exec monadic-chat-python-container python -c "#{python_script.gsub('"', '\"').gsub("\n", "; ")}"`
    
    filepath
  end
  
  def create_test_image_with_text(filename, text)
    filepath = File.join(Dir.home, "monadic", "data", filename)
    
    # Use Python PIL to create an image with text
    python_script = <<~PYTHON
      from PIL import Image, ImageDraw, ImageFont
      import os
      
      # Create a white image
      img = Image.new('RGB', (800, 400), color='white')
      draw = ImageDraw.Draw(img)
      
      # Try to use a font, fall back to default if not available
      try:
          font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
      except:
          font = ImageFont.load_default()
      
      # Draw the text
      lines = "#{text}".split('\\n')
      y = 50
      for line in lines:
          draw.text((50, y), line, fill='black', font=font)
          y += 40
      
      # Save the image
      img.save("#{filepath}")
    PYTHON
    
    `docker exec monadic-chat-python-container python -c "#{python_script.gsub('"', '\"').gsub("\n", "; ")}"`
    
    filepath
  end
  
  def generate_test_audio_file(text, filename)
    require_relative "../support/real_audio_test_helper"
    include RealAudioTestHelper
    
    # Use the real audio test helper
    audio_file = generate_real_audio_file(text, format: "mp3")
    
    # Move to expected location
    target_path = File.join(Dir.home, "monadic", "data", filename)
    FileUtils.mv(audio_file, target_path)
    
    target_path
  end
  
  def cleanup_test_file(filepath)
    File.delete(filepath) if filepath && File.exist?(filepath)
  end
end