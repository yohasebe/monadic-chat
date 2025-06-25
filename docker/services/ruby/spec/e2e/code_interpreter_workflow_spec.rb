# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'

RSpec.describe "Code Interpreter E2E Workflow", type: :e2e do
  include E2EHelper
  include ValidationHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
  end

  describe "Python Code Execution" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "executes calculations and shows output" do
      message = "Calculate the sum of squares from 1 to 5 using Python"
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(code_execution_attempted?(response)).to be true
    end

    it "persists variables between executions" do
      # Create a variable
      message1 = "Create a list called 'numbers' with values [10, 20, 30, 40, 50]"
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection)
      expect(code_execution_attempted?(response1)).to be true
      
      ws_connection[:messages].clear
      
      # Use the variable
      message2 = "Using the 'numbers' list, calculate the average"
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection)
      expect(code_execution_attempted?(response2)).to be true
    end

    it "handles errors gracefully" do
      message = "Try to divide by zero and explain what happens"
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      expect(response.downcase).to match(/error|zero|division/i)
    end
  end

  describe "Data Science Workflows" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "performs data analysis with pandas" do
      message = <<~MSG
        Create a pandas DataFrame with sample sales data (5 products, prices, quantities)
        and calculate total revenue per product
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection, timeout: 60)
      
      expect(valid_response?(response)).to be true
      expect(code_execution_attempted?(response)).to be true
    end

    it "creates visualizations" do
      message = "Create a simple bar chart showing values [10, 25, 15, 30, 20] with matplotlib"
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection, timeout: 90)
      
      expect(response.downcase).to match(/chart|plot|matplotlib|created|saved/i)
    end

    it "uses numpy for calculations" do
      message = "Use numpy to create a 3x3 matrix and calculate its determinant"
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(response.downcase).to match(/numpy|matrix|determinant/i)
      expect(code_execution_attempted?(response)).to be true
    end
  end

  describe "File Operations" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "processes JSON data" do
      message = <<~MSG
        Create a JSON structure with user data (name, age, city) for 3 users
        and then extract all names
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(code_execution_attempted?(response)).to be true
    end

    it "works with CSV data" do
      message = <<~MSG
        Create CSV data for a simple inventory (product, price, stock)
        and find the most expensive product
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/csv|product|price|expensive/i)
    end
  end

  describe "Complex Multi-Step Workflows" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
    end

    it "completes a data pipeline" do
      # Step 1: Generate data
      message1 = "Generate random sales data for 12 months"
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection, timeout: 60)
      expect(code_execution_attempted?(response1)).to be true
      
      ws_connection[:messages].clear
      
      # Step 2: Analyze data
      message2 = "Calculate quarterly totals from the monthly data"
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection, timeout: 60)
      expect(code_execution_attempted?(response2)).to be true
      
      ws_connection[:messages].clear
      
      # Step 3: Visualize
      message3 = "Create a visualization showing the quarterly trends"
      send_chat_message(ws_connection, message3, app: "CodeInterpreterOpenAI")
      response3 = wait_for_response(ws_connection, timeout: 90)
      expect(response3).not_to be_empty
    end
  end
end