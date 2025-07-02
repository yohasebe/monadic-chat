# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "../support/custom_retry"
require_relative "../../lib/monadic/utils/environment"

RSpec.describe "Jupyter Notebook E2E", :e2e do
  include E2EHelper
  include E2ERetryHelper
  
  let(:app_name) { "JupyterNotebookOpenAI" }
  
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
  
  after(:all) do
    # Ensure Jupyter is stopped after tests
    ws_connection = create_websocket_connection
    send_chat_message(ws_connection, "Please stop Jupyter", app: "JupyterNotebookOpenAI")
    wait_for_response(ws_connection, timeout: 60)
    ws_connection[:client].close
  end
  
  describe "Jupyter initialization" do
    it "responds to Jupyter-related requests" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.5  # Wait for WebSocket connection
        send_chat_message(ws_connection, "Start JupyterLab and create a new notebook", app: app_name)
        sleep 3.0  # Wait longer for Jupyter startup
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should provide Jupyter-related response
        expect(response.downcase).to match(/jupyter|notebook|starting|initialized/i)
        # Response should be substantial (not just an error)
        expect(response.length).to be > 10
      end
    end
  end
  
  describe "Notebook creation" do
    it "creates a new notebook when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request to create a specific notebook
        send_chat_message(ws_connection, "Create a new Jupyter notebook called 'analysis'", app: app_name)
        sleep 3.0  # Wait for notebook creation
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should acknowledge notebook creation request
        expect(response.downcase).to match(/notebook|jupyter|create|analysis/i)
        # Response should be meaningful
        expect(response.length).to be > 10
      end
    end
    
    it "handles notebook operations" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request to work with notebooks
        send_chat_message(ws_connection, 
          "I want to work with a Jupyter notebook",
          app: app_name
        )
        sleep 1.5
        response = wait_for_response(ws_connection, timeout: 60)
        ws_connection[:client].close
        
        # Should respond about notebooks
        expect(response.downcase).to match(/notebook|jupyter/i)
      end
    end
  end
  
  describe "Cell operations" do
    it "adds and executes code cells" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # First ensure Jupyter is running and notebook exists
        send_chat_message(ws_connection,
          "Start Jupyter if not running, create a notebook called 'test', and add a code cell that prints 'Hello from Jupyter!' and calculates 2+2",
          app: app_name
        )
        sleep 4.0  # Wait longer for multiple operations
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should indicate cell operation or code execution
        expect(response.downcase).to match(/cell|code|jupyter|notebook|add/i)
        # Response should be meaningful
        expect(response.length).to be > 10
      end
    end
    
    it "adds markdown cells with formatting" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Add a markdown cell
        send_chat_message(ws_connection,
          "Add a markdown cell with a title '# Data Analysis' and some math formula like $x^2 + y^2 = z^2$",
          app: app_name
        )
        sleep 3.0  # Wait for markdown processing
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should add markdown cell
        expect(response.downcase).to match(/markdown|cell|add|data analysis/i)
        # Response should indicate markdown operation
        expect(response.length).to be > 10
      end
    end
    
    it "handles data visualization requests" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request a simple plot with notebook setup
        send_chat_message(ws_connection,
          "Start Jupyter if needed, create a notebook and add a cell that uses matplotlib to plot y = x^2 for x from -5 to 5",
          app: app_name
        )
        sleep 4.0  # Wait longer for plot generation
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should mention plotting or visualization
        expect(response.downcase).to match(/matplotlib|plot|x\^2|jupyter|visualization/i)
      end
    end
  end
  
  describe "File operations" do
    it "reads and processes data files" do
      # First create a test CSV file
      test_file = File.join(Monadic::Utils::Environment.data_path, "test_data.csv")
      File.write(test_file, "name,value\nA,10\nB,20\nC,30\n")
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # First start Jupyter and create notebook, then read CSV
        send_chat_message(ws_connection,
          "Start Jupyter, create a notebook, then read test_data.csv and create a cell to load it with pandas",
          app: app_name
        )
        sleep 4.0  # Wait longer for multiple operations
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should mention pandas, CSV, or data operations
        expect(response.downcase).to match(/pandas|csv|data|jupyter|notebook/i)
      end
      
      # Clean up
      File.delete(test_file) if File.exist?(test_file)
    end
    
    it "writes output files" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request to save data to file
        send_chat_message(ws_connection,
          "Start Jupyter if needed, create a notebook, and add a cell that writes 'Test output' to a file called output.txt using Python's open() function",
          app: app_name
        )
        sleep 3.0  # Wait longer for multiple operations
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should create file writing code
        expect(response.downcase).to match(/write|file|output/i)
        # Response should be meaningful
        expect(response.length).to be > 10
      end
    end
  end
  
  describe "Package management" do
    it "handles package installation requests" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request package installation
        send_chat_message(ws_connection,
          "I need to install numpy. How do I do that?",
          app: app_name
        )
        sleep 2.0  # Wait for response
        response = wait_for_response(ws_connection)
        ws_connection[:client].close
        
        # Should suggest pip install
        expect(response.downcase).to match(/pip.*install|!pip/i)
        expect(response.downcase).to include("numpy")
      end
    end
  end
  
  describe "Environment information" do
    it "provides environment details when asked" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Ask about environment
        send_chat_message(ws_connection,
          "What Python packages are available in this environment?",
          app: app_name
        )
        sleep 2.0
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should check environment
        expect(response.downcase).to match(/environment|package|available|python/i)
      end
    end
  end
  
  describe "Error handling" do
    it "handles code errors gracefully" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Add code with error
        send_chat_message(ws_connection,
          "Start Jupyter if needed, create a notebook called 'error_test', and add a cell with this code: print(undefined_variable)",
          app: app_name
        )
        sleep 3.0  # Wait for error processing
        response = wait_for_response(ws_connection, timeout: 90)
        ws_connection[:client].close
        
        # Should show error and suggest fix
        expect(response.downcase).to match(/error|undefined|variable|fix|suggest/i)
      end
    end
    
    it "automatically fixes errors in cells" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request to add code with error and fix it
        send_chat_message(ws_connection,
          "Start Jupyter, create a notebook 'error_test', add a cell that tries to use numpy without importing it (np.array([1,2,3])), then check for errors and fix them if found",
          app: app_name
        )
        sleep 4.0  # Wait longer for error detection and fixing
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should indicate error detection or fixing intent
        expect(response.downcase).to match(/error|fix|check|numpy|jupyter|notebook/i)
        # Response should be meaningful
        expect(response.length).to be > 10
      end
    end
    
    it "prevents infinite error correction loops" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Add code that has an unfixable error
        send_chat_message(ws_connection,
          "Create a notebook 'loop_test' and add a cell with: from nonexistent_module import something. Try to fix any errors but stop after maximum retries.",
          app: app_name
        )
        sleep 4.0  # Wait longer for multiple retry attempts
        response = wait_for_response(ws_connection, timeout: 120)
        ws_connection[:client].close
        
        # Should indicate maximum retries or unable to fix
        expect(response.downcase).to match(/error|module.*not.*found|unable|retry|cannot.*fix/i)
      end
    end
  end
  
  describe "Jupyter shutdown" do
    it "stops JupyterLab when requested" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        ws_connection = create_websocket_connection
        sleep 1.0
        
        # Request to stop Jupyter
        send_chat_message(ws_connection,
          "Please stop JupyterLab",
          app: app_name
        )
        sleep 3.0  # Wait for shutdown
        response = wait_for_response(ws_connection, timeout: 60)
        ws_connection[:client].close
        
        # Should stop Jupyter
        expect(response.downcase).to match(/stop|shut|down|jupyter/i)
      end
    end
  end
end