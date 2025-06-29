# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "../support/custom_retry"
require "fileutils"

RSpec.describe "Coding Assistant E2E", :e2e do
  include E2EHelper
  include E2ERetryHelper
  
  let(:app_name) { "CodingAssistantOpenAI" }
  
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
  
  describe "Coding Assistant workflow" do
    it "responds to greeting appropriately" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0  # Wait longer for WebSocket connection to stabilize
        send_chat_message(ws_connection, "Hello", app: app_name)
        sleep 1.0  # Wait longer before checking response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should provide a greeting and be ready to help with coding
        expect(response.downcase).to match(/hello|hi|help|assist|code/i)
        expect(response.length).to be > 10
      end
    end
  end
  
  describe "Code writing assistance" do
    it "writes a simple function when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection, 
          "Write a Python function to calculate factorial",
          app: app_name
        )
        sleep 0.5
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        expect(response).to include("def")
        expect(response).to match(/factorial|recursion|iteration/i)
        expect(response).to include("return")
      end
    end
    
    it "provides code explanation when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection,
          "Explain this code: def fib(n): return n if n <= 1 else fib(n-1) + fib(n-2)",
          app: app_name
        )
        sleep 0.5
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        expect(response.downcase).to match(/fibonacci|recursive|sequence/i)
        expect(response.downcase).to match(/base case|recursion/i)
      end
    end
  end
  
  describe "Code with __DATA__ separator" do
    it "processes code improvement requests with data separator" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0  # Wait longer for connection
        
        message = <<~MSG
        Please optimize this code for better performance
        __DATA__
        def find_primes(n):
            primes = []
            for num in range(2, n + 1):
                is_prime = True
                for i in range(2, num):
                    if num % i == 0:
                        is_prime = False
                        break
                if is_prime:
                    primes.append(num)
            return primes
        MSG
        
        send_chat_message(ws_connection, message, app: app_name)
        sleep 1.5  # Wait longer for code analysis
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should suggest optimization like Sieve of Eratosthenes
        expect(response.downcase).to match(/optimize|sieve|performance|efficient/i)
        expect(response).to include("def")
      end
    end
  end
  
  describe "Multi-language support" do
    it "writes code in different programming languages" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection,
          "Write a hello world program in Ruby, Python, and JavaScript",
          app: app_name
        )
        sleep 0.5
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should include examples in all three languages
        expect(response).to include("puts")  # Ruby
        expect(response).to include("print")  # Python
        expect(response).to include("console.log")  # JavaScript
      end
    end
  end
  
  describe "Code refactoring assistance" do
    it "suggests refactoring improvements" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        
        message = <<~MSG
        How can I refactor this code?
        __DATA__
        def process_data(data):
            result = []
            for item in data:
                if item > 0:
                    if item % 2 == 0:
                        result.append(item * 2)
                    else:
                        result.append(item * 3)
            return result
        MSG
        
        send_chat_message(ws_connection, message, app: app_name)
        sleep 1.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should suggest improvements like list comprehension or functional approach
        expect(response.downcase).to match(/refactor|improve|comprehension|readable/i)
      end
    end
  end
  
  describe "Debugging assistance" do
    it "helps identify and fix bugs in code" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        
        message = <<~MSG
        This code has a bug. Can you help fix it?
        __DATA__
        def divide_list(numbers, divisor):
            result = []
            for num in numbers:
                result.append(num / divisor)
            return result
        MSG
        
        send_chat_message(ws_connection, message, app: app_name)
        sleep 1.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should identify division by zero issue
        expect(response.downcase).to match(/zero|division|error|exception|check/i)
      end
    end
  end
  
  describe "Algorithm implementation" do
    it "implements algorithms when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        send_chat_message(ws_connection,
          "Implement binary search algorithm in Python",
          app: app_name
        )
        sleep 0.5
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        expect(response).to include("def")
        expect(response.downcase).to match(/binary|search|middle|left|right/i)
        expect(response).to include("while").or include("if")
      end
    end
  end
  
  describe "Code documentation" do
    it "adds documentation to existing code" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 0.5
        
        message = <<~MSG
        Add docstrings and comments to this code
        __DATA__
        def calculate_bmi(weight, height):
            return weight / (height ** 2)
        MSG
        
        send_chat_message(ws_connection, message, app: app_name)
        sleep 0.5
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should add docstrings and comments
        expect(response).to include('"""').or include("'''")
        expect(response.downcase).to match(/param|return|bmi|body mass index/i)
      end
    end
  end
  
  describe "Long response handling" do
    it "handles long code generation requests" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0  # Wait longer for connection
        send_chat_message(ws_connection,
          "Write a complete REST API server with authentication, database models, and endpoints in Python using Flask",
          app: app_name
        )
        sleep 1.5  # Wait longer for complex request
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should provide Flask implementation
        expect(response.downcase).to match(/flask|api|import/i)
        # Check if it's a substantial response
        expect(response.length).to be > 500
        # Response should include code blocks
        expect(response).to include("```")
      end
    end
  end
end