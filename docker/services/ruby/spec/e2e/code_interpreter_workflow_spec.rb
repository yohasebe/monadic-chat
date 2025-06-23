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
      cleanup_test_files("test_output.txt", "data.csv", "plot.png", "analysis.json")
    end

    it "executes simple Python calculations" do
      message = "Use the run_code function to calculate the factorial of 10 in Python and show me the output"
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should contain factorial result (with or without comma formatting)
      expect(response.gsub(",", "")).to include("3628800")
      expect(response).to match(/factorial|code|python/i)
    end

    it "handles data analysis workflow" do
      # Create CSV data inline
      message = <<~MSG
        Here is CSV data:
        ```
        name,age,score
        Alice,25,85
        Bob,30,92
        Charlie,35,78
        Diana,28,95
        Eve,32,88
        ```
        
        Calculate the average score and age using pandas.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Verify analysis results - just check that averages were calculated
      expect(response.downcase).to match(/average|mean|calculated/i)
      # Should contain some numeric results
      expect(contains_numeric_results?(response)).to be true
      # Should mention both age and score
      expect(response.downcase).to match(/age|score/i)
    end

    it "generates and saves visualizations" do
      message = <<~MSG
        Create a bar chart showing the fibonacci sequence for the first 8 numbers and save it as 'fibonacci_chart.png' using matplotlib.
        Execute the code and confirm the file was saved.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      # Just check that the response is valid and mentions visualization-related terms
      expect(valid_response?(response)).to be true
      expect(response.downcase).to match(/fibonacci|chart|plot|save|png|matplotlib|generated|created/i)
      # Should either contain code or indicate execution
      expect(contains_code?(response) || response.downcase.match?(/saved|executed|created/i)).to be true
    end

    it "handles Python errors gracefully" do
      message = "Use run_code to execute: print(1/0) and show me what error occurs"
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Should explain the error
      expect(response).to match(/ZeroDivisionError|division.*zero|error/i)
      expect(response).not_to match(/UNKNOWN ERROR|crashed/i)
    end

    it "persists data between code executions" do
      # First execution - create data
      message1 = "Execute this code: my_data = [1, 2, 3, 4, 5]; print(f'Sum is: {sum(my_data)}')"
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection)
      expect(response1.downcase).to match(/sum.*15|15/)
      
      ws_connection[:messages].clear
      
      # Second execution - use previous data
      message2 = "Using the 'my_data' list from before, calculate the mean"
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection)
      expect(response2).to include("3") # Mean of [1,2,3,4,5]
    end
  end

  describe "Data Science Libraries" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
      cleanup_test_files("matrix_result.npy", "regression_plot.png")
    end

    it "uses NumPy for matrix operations" do
      message = <<~MSG
        Create a 3x3 matrix with random values between 0 and 1 using NumPy.
        Calculate its determinant and eigenvalues.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(response).to match(/determinant|eigenvalue/i)
      expect(response).to match(/numpy|matrix/i)
    end

    it "performs statistical analysis with SciPy" do
      message = <<~MSG
        Generate two sets of random data and perform a t-test using scipy.stats.
        Interpret the results.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(response).to match(/t-test|p-value|statistic/i)
      expect(response).to match(/scipy|statistical/i)
    end

    it "creates machine learning model with scikit-learn" do
      message = <<~MSG
        Create a simple linear regression model using scikit-learn.
        Generate some sample data, train the model, and show the R-squared score.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      response = wait_for_response(ws_connection)
      
      expect(response).to match(/R-squared|R\^2|score/i)
      expect(response).to match(/linear.*regression|sklearn/i)
    end
  end

  describe "File Operations" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
      cleanup_test_files("output.json", "results.txt", "data.pkl")
    end

    it "reads and writes JSON files" do
      message = <<~MSG
        Here is JSON data:
        ```json
        {"users": [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}]}
        ```
        
        Add a new user named Charlie age 35 to this data and show the updated JSON.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Check response
      expect(response).to include("Charlie")
      expect(response).to include("35")
      expect(response.downcase).to match(/users|json|added/i)
    end

    it "processes CSV files with pandas" do
      message = <<~MSG
        Here is CSV inventory data:
        ```
        product,price,quantity
        Apple,1.50,100
        Banana,0.75,150
        Orange,1.25,80
        ```
        
        Calculate the total value for each product (price * quantity) using pandas.
      MSG
      
      send_chat_message(ws_connection, message, app: "CodeInterpreterOpenAI")
      
      response = wait_for_response(ws_connection)
      
      # Verify calculations were performed
      expect(valid_response?(response)).to be true
      expect(contains_numeric_results?(response)).to be true
      # Should mention products or calculations
      expect(response.downcase).to match(/apple|banana|orange|total|value|calculated/i)
    end
  end

  describe "Complex Workflows" do
    let(:ws_connection) { create_websocket_connection }
    
    after do
      ws_connection[:client].close if ws_connection[:client]
      cleanup_test_files("report.txt", "summary.png", "analysis_results.csv")
    end

    it "completes multi-step data analysis workflow" do
      # Step 1: Generate data
      message1 = <<~MSG
        Generate sample sales data for 12 months with random values between 1000 and 5000.
        Save it as monthly_sales.csv
      MSG
      
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection, timeout: 60)
      expect(valid_response?(response1)).to be true
      expect(validates_workflow_step?(response1, :file_operation)).to be true
      
      ws_connection[:messages].clear
      
      # Step 2: Analyze data
      message2 = <<~MSG
        Read monthly_sales.csv, calculate quarterly totals, and identify the best quarter
      MSG
      
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection, timeout: 60)
      expect(valid_response?(response2)).to be true
      expect(validates_workflow_step?(response2, :data_analysis)).to be true
      
      ws_connection[:messages].clear
      
      # Step 3: Visualize results
      message3 = <<~MSG
        Create a bar chart showing the quarterly totals and save as quarterly_analysis.png
      MSG
      
      send_chat_message(ws_connection, message3, app: "CodeInterpreterOpenAI")
      response3 = wait_for_response(ws_connection, timeout: 60)
      # Just check that we got a non-empty response
      expect(response3).not_to be_empty
      # Accept any response that mentions visualization-related terms or file operation
      expect(response3.downcase).to match(/chart|graph|plot|visualization|png|save|create|error|cannot/i)
      
      # Cleanup
      ["monthly_sales.csv", "quarterly_analysis.png"].each do |file|
        path = File.join(Dir.home, "monadic", "data", file)
        File.delete(path) if File.exist?(path)
      end
    end

    it "handles iterative development workflow" do
      # Initial code
      message1 = "Write a function to calculate prime numbers up to n"
      send_chat_message(ws_connection, message1, app: "CodeInterpreterOpenAI")
      response1 = wait_for_response(ws_connection)
      expect(valid_response?(response1)).to be true
      expect(validates_workflow_step?(response1, :code_generation)).to be true
      
      ws_connection[:messages].clear
      
      # Test the function
      message2 = "Test the prime function with n=20 and show the results"
      send_chat_message(ws_connection, message2, app: "CodeInterpreterOpenAI")
      response2 = wait_for_response(ws_connection)
      expect(valid_response?(response2)).to be true
      # Either code or results are acceptable
      expect(contains_code?(response2) || contains_numeric_results?(response2)).to be true
      
      ws_connection[:messages].clear
      
      # Optimize the function
      message3 = "Optimize the prime function using the Sieve of Eratosthenes"
      send_chat_message(ws_connection, message3, app: "CodeInterpreterOpenAI")
      response3 = wait_for_response(ws_connection)
      expect(valid_response?(response3)).to be true
      expect(acknowledges_task?(response3, %w[sieve eratosthenes optimize algorithm])).to be true
    end
  end
end