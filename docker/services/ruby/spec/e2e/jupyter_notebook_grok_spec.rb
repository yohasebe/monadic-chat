# frozen_string_literal: true

require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "Jupyter Notebook Grok Integration", :e2e do
  let(:app_name) { "JupyterNotebookGrok" }
  let(:app) { 
    # Create a new instance of the app
    JupyterNotebookGrok.new rescue APPS[app_name]
  }
  let(:data_dir) { File.expand_path("../../data", __dir__) }
  
  before(:all) do
    # Ensure XAI_API_KEY is available
    unless ENV["XAI_API_KEY"] || CONFIG["XAI_API_KEY"]
      skip "XAI_API_KEY not configured"
    end
  end
  
  before(:each) do
    # Clean up data directory before each test
    FileUtils.rm_rf(Dir.glob(File.join(data_dir, "*.ipynb")))
    
    # Kill any running Jupyter processes
    system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
    sleep 1
  end
  
  after(:each) do
    # Clean up after tests
    system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
    FileUtils.rm_rf(Dir.glob(File.join(data_dir, "*.ipynb")))
  end
  
  describe "Tool Execution" do
    context "when starting JupyterLab" do
      it "successfully starts JupyterLab server" do
        result = app.run_jupyter(command: "start")
        
        expect(result).to include("JupyterLab")
        expect(result).to match(/running|started/i)
        
        # Verify process is actually running
        sleep 2
        ps_output = `ps aux | grep jupyter-lab | grep -v grep`
        expect(ps_output).not_to be_empty
      end
      
      it "handles already running JupyterLab gracefully" do
        # Start JupyterLab first
        app.run_jupyter(command: "start")
        sleep 2
        
        # Try to start again
        result = app.run_jupyter(command: "start")
        expect(result).to match(/already running/i)
      end
    end
    
    context "when creating notebooks" do
      before do
        app.run_jupyter(command: "start")
        sleep 2
      end
      
      it "creates a new Jupyter notebook" do
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        result = app.create_jupyter_notebook(filename: "test_notebook")
        
        expect(result).to include("http://")
        expect(result).to include(".ipynb")
        
        # Verify file was created
        notebooks = Dir.glob(File.join(data_dir, "*.ipynb"))
        expect(notebooks).not_to be_empty
        expect(notebooks.first).to match(/test_notebook.*\.ipynb/)
      end
      
      it "creates notebooks with unique timestamps" do
        result1 = app.create_jupyter_notebook(filename: "notebook1")
        sleep 1
        result2 = app.create_jupyter_notebook(filename: "notebook2")
        
        # Extract filenames from results
        filename1 = result1.match(/([^\/]+\.ipynb)/)[1]
        filename2 = result2.match(/([^\/]+\.ipynb)/)[1]
        
        expect(filename1).not_to eq(filename2)
        
        # Both files should exist
        expect(File.exist?(File.join(data_dir, filename1))).to be true
        expect(File.exist?(File.join(data_dir, filename2))).to be true
      end
    end
    
    context "when adding cells to notebook" do
      let(:notebook_filename) { "test_notebook_#{Time.now.to_i}.ipynb" }
      
      before do
        app.run_jupyter(command: "start")
        sleep 2
        @notebook_path = app.create_jupyter_notebook(filename: "test")
        @actual_filename = @notebook_path.match(/([^\/]+\.ipynb)/)[1]
      end
      
      it "adds code cells to notebook" do
        cells = [
          {
            "cell_type" => "code",
            "source" => ["import numpy as np", "import matplotlib.pyplot as plt"]
          },
          {
            "cell_type" => "code", 
            "source" => ["x = np.linspace(0, 10, 100)", "y = np.sin(x)"]
          }
        ]
        
        result = app.add_jupyter_cells(
          filename: @actual_filename,
          cells: cells,
          run: false
        )
        
        expect(result).to include("added")
        
        # Verify notebook content
        notebook_path = File.join(data_dir, @actual_filename)
        notebook_content = JSON.parse(File.read(notebook_path))
        
        expect(notebook_content["cells"].length).to eq(2)
        expect(notebook_content["cells"][0]["cell_type"]).to eq("code")
      end
      
      it "adds markdown cells to notebook" do
        cells = [
          {
            "cell_type" => "markdown",
            "source" => "# Test Notebook\n\nThis is a test."
          }
        ]
        
        result = app.add_jupyter_cells(
          filename: @actual_filename,
          cells: cells,
          run: false
        )
        
        expect(result).to include("added")
        
        # Verify notebook content
        notebook_path = File.join(data_dir, @actual_filename)
        notebook_content = JSON.parse(File.read(notebook_path))
        
        expect(notebook_content["cells"].any? { |c| c["cell_type"] == "markdown" }).to be true
      end
      
      it "executes cells when run flag is true" do
        cells = [
          {
            "cell_type" => "code",
            "source" => "result = 2 + 2\nprint(f'Result: {result}')"
          }
        ]
        
        result = app.add_jupyter_cells(
          filename: @actual_filename,
          cells: cells,
          run: true
        )
        
        # When run=true, it should execute and potentially show output
        expect(result).to include("cells")
      end
    end
    
    context "when deleting cells" do
      before do
        app.run_jupyter(command: "start")
        sleep 2
        @notebook_path = app.create_jupyter_notebook(filename: "test")
        @actual_filename = @notebook_path.match(/([^\/]+\.ipynb)/)[1]
        
        # Add some cells first
        cells = [
          { "cell_type" => "code", "source" => "print('Cell 0')" },
          { "cell_type" => "code", "source" => "print('Cell 1')" },
          { "cell_type" => "code", "source" => "print('Cell 2')" }
        ]
        app.add_jupyter_cells(filename: @actual_filename, cells: cells, run: false)
      end
      
      it "deletes a cell by index" do
        result = app.delete_jupyter_cell(filename: @actual_filename, index: 1)
        
        expect(result).to include("deleted")
        
        # Verify cell was deleted
        notebook_path = File.join(data_dir, @actual_filename)
        notebook_content = JSON.parse(File.read(notebook_path))
        
        expect(notebook_content["cells"].length).to eq(2)
        # First cell should still be "Cell 0"
        expect(notebook_content["cells"][0]["source"]).to include("Cell 0")
        # Second cell should now be "Cell 2" (since Cell 1 was deleted)
        expect(notebook_content["cells"][1]["source"]).to include("Cell 2")
      end
    end
    
    context "when updating cells" do
      before do
        app.run_jupyter(command: "start")
        sleep 2
        @notebook_path = app.create_jupyter_notebook(filename: "test")
        @actual_filename = @notebook_path.match(/([^\/]+\.ipynb)/)[1]
        
        # Add a cell to update
        cells = [{ "cell_type" => "code", "source" => "print('Original')" }]
        app.add_jupyter_cells(filename: @actual_filename, cells: cells, run: false)
      end
      
      it "updates cell content" do
        result = app.update_jupyter_cell(
          filename: @actual_filename,
          index: 0,
          content: "print('Updated')",
          cell_type: "code"
        )
        
        expect(result).to include("updated")
        
        # Verify cell was updated
        notebook_path = File.join(data_dir, @actual_filename)
        notebook_content = JSON.parse(File.read(notebook_path))
        
        expect(notebook_content["cells"][0]["source"]).to include("Updated")
      end
    end
    
    context "when listing notebooks" do
      before do
        app.run_jupyter(command: "start")
        sleep 2
      end
      
      it "lists all notebooks in data directory" do
        # Create a few notebooks
        app.create_jupyter_notebook(filename: "notebook1")
        app.create_jupyter_notebook(filename: "notebook2")
        
        result = app.list_jupyter_notebooks
        
        expect(result).to include("notebook1")
        expect(result).to include("notebook2")
        expect(result).to include(".ipynb")
      end
      
      it "returns appropriate message when no notebooks exist" do
        result = app.list_jupyter_notebooks
        
        expect(result).to match(/no.*notebooks?|empty/i)
      end
    end
  end
  
  describe "Tool Call Depth Limit" do
    it "respects MAX_FUNC_CALLS limit" do
      # This test verifies that the system prevents infinite loops
      # We can't easily test the actual limit without API calls,
      # but we can verify the constant exists and is reasonable
      expect(GrokHelper::MAX_FUNC_CALLS).to be_a(Integer)
      expect(GrokHelper::MAX_FUNC_CALLS).to be > 0
      expect(GrokHelper::MAX_FUNC_CALLS).to be <= 30  # Reasonable upper limit
    end
  end
  
  describe "Error Handling" do
    it "handles missing notebook gracefully" do
      app.run_jupyter(command: "start")
      sleep 2
      
      result = app.get_jupyter_cells_with_results(filename: "nonexistent.ipynb")
      
      expect(result).to match(/not found|does not exist|error/i)
    end
    
    it "handles invalid cell index" do
      app.run_jupyter(command: "start")
      sleep 2
      @notebook_path = app.create_jupyter_notebook(filename: "test")
      @actual_filename = @notebook_path.match(/([^\/]+\.ipynb)/)[1]
      
      result = app.delete_jupyter_cell(filename: @actual_filename, index: 999)
      
      expect(result).to match(/out of range|invalid|error/i)
    end
  end
  
  describe "File Operations" do
    before do
      # Create a test file to read
      File.write(File.join(data_dir, "test.txt"), "Test content")
      File.write(File.join(data_dir, "test.py"), "print('Hello')")
    end
    
    after do
      FileUtils.rm_f(File.join(data_dir, "test.txt"))
      FileUtils.rm_f(File.join(data_dir, "test.py"))
    end
    
    it "fetches text from files" do
      result = app.fetch_text_from_file(file: "test.txt")
      expect(result).to eq("Test content")
      
      result = app.fetch_text_from_file(file: "test.py")
      expect(result).to eq("print('Hello')")
    end
    
    it "writes content to files" do
      app.write_to_file(filename: "output.txt", content: "New content")
      
      expect(File.exist?(File.join(data_dir, "output.txt"))).to be true
      expect(File.read(File.join(data_dir, "output.txt"))).to eq("New content")
      
      # Clean up
      FileUtils.rm_f(File.join(data_dir, "output.txt"))
    end
  end
  
  describe "Code Execution" do
    it "executes Python code" do
      result = app.run_code(
        command: "python",
        code: "print('Hello from Python')",
        extension: "py"
      )
      
      expect(result).to include("Hello from Python")
    end
    
    it "handles code execution errors" do
      result = app.run_code(
        command: "python",
        code: "raise ValueError('Test error')",
        extension: "py"
      )
      
      expect(result).to match(/ValueError|error/i)
    end
  end
end