# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "fileutils"

RSpec.describe "Jupyter Controller Integration", type: :integration do
  let(:jupyter_controller_path) { File.expand_path("../../python/scripts/services/jupyter_controller.py", __dir__) }
  let(:data_dir) { File.expand_path("~/monadic/data") }
  let(:test_notebook_name) { "test_notebook_#{Time.now.to_i}" }
  
  before(:all) do
    # Ensure data directory exists
    FileUtils.mkdir_p(File.expand_path("~/monadic/data"))
  end
  
  after(:each) do
    # Clean up test notebooks
    Dir.glob(File.join(data_dir, "#{test_notebook_name}*.ipynb")).each do |file|
      FileUtils.rm_f(file)
    end
    Dir.glob(File.join(data_dir, "test_*.json")).each do |file|
      FileUtils.rm_f(file)
    end
  end
  
  describe "Basic Operations" do
    it "creates a new notebook" do
      output, status = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      
      expect(status.success?).to be true
      expect(output).to include("Notebook created")
      
      # Verify notebook file exists
      notebooks = Dir.glob(File.join(data_dir, "#{test_notebook_name}*.ipynb"))
      expect(notebooks.length).to eq(1)
    end
    
    it "adds cells to an existing notebook" do
      # First create a notebook
      output, status = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      expect(status.success?).to be true
      
      # Extract the actual notebook filename from output
      match = output.match(/Notebook created: (.+\.ipynb)/)
      expect(match).not_to be_nil
      notebook_filename = match[1].gsub(".ipynb", "")
      
      # Add cells
      cells = [
        { type: "markdown", content: "# Test Header" },
        { type: "code", content: "print('Hello from test')" }
      ]
      
      output, status = Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      expect(status.success?).to be true
      expect(output).to include("Cells added to notebook")
    end
    
    it "handles various cell source formats" do
      # Create notebook
      output, status = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      # Test different cell formats
      cells = [
        # Standard format with 'content'
        { type: "markdown", content: "# Standard format" },
        # Alternative format with 'source' as string
        { cell_type: "code", source: "x = 42" },
        # Alternative format with 'source' as array
        { cell_type: "code", source: ["import numpy as np\n", "import pandas as pd\n", "print('Multi-line')"] }
      ]
      
      output, status = Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      expect(status.success?).to be true
      expect(output).to include("Cells added to notebook")
    end
    
    it "searches for content in cells" do
      # Create and populate notebook
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      cells = [
        { type: "markdown", content: "# Introduction to Ruby" },
        { type: "code", content: "def hello_ruby\n  puts 'Hello Ruby'\nend" },
        { type: "markdown", content: "Ruby is a dynamic language" }
      ]
      
      Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      # Search for "Ruby"
      output, status = Open3.capture2("python3", jupyter_controller_path, "search", notebook_filename, "Ruby")
      
      expect(status.success?).to be true
      expect(output).to include("Found keyword in Cell")
      expect(output.scan(/Ruby/).count).to be >= 3  # Should find multiple occurrences
    end
    
    it "updates a cell" do
      # Create notebook with initial content
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      cells = [{ type: "markdown", content: "# Original Title" }]
      Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      # Update the cell
      output, status = Open3.capture2("python3", jupyter_controller_path, "update", notebook_filename, "0", "# Updated Title", "markdown")
      
      expect(status.success?).to be true
      expect(output).to include("Cell 0 updated")
      
      # Verify update by searching
      output, _ = Open3.capture2("python3", jupyter_controller_path, "search", notebook_filename, "Updated")
      expect(output).to include("Updated Title")
    end
    
    it "deletes a cell" do
      # Create notebook with multiple cells
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      cells = [
        { type: "markdown", content: "# Cell 1" },
        { type: "code", content: "# To be deleted" },
        { type: "markdown", content: "# Cell 3" }
      ]
      Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      # Delete middle cell
      output, status = Open3.capture2("python3", jupyter_controller_path, "delete", notebook_filename, "1")
      
      expect(status.success?).to be true
      expect(output).to include("Cell 1 deleted")
      
      # Verify deletion
      output, _ = Open3.capture2("python3", jupyter_controller_path, "search", notebook_filename, "To be deleted")
      expect(output).not_to include("Found keyword")
    end
    
    it "adds cells from JSON file" do
      # Create notebook
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      # Create JSON file with cells
      json_filename = "test_cells_#{Time.now.to_i}.json"
      json_path = File.join(data_dir, json_filename)
      
      cells = [
        { type: "markdown", content: "# From JSON File" },
        { type: "code", content: "data = [1, 2, 3, 4, 5]" }
      ]
      
      File.write(json_path, JSON.pretty_generate(cells))
      
      # Add cells from JSON
      output, status = Open3.capture2("python3", jupyter_controller_path, "add_from_json", notebook_filename, json_filename)
      
      expect(status.success?).to be true
      expect(output).to include("Cells added to notebook")
      
      # Verify cells were added
      output, _ = Open3.capture2("python3", jupyter_controller_path, "search", notebook_filename, "From JSON")
      expect(output).to include("From JSON File")
    end
  end
  
  describe "Error Handling" do
    it "handles non-existent notebook gracefully" do
      output, status = Open3.capture2("python3", jupyter_controller_path, "read", "non_existent_notebook")
      
      expect(status.success?).to be true  # Script should exit cleanly
      expect(output).to include("does not exist")
    end
    
    it "handles invalid JSON input" do
      # Create notebook
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      # Try to add cells with invalid JSON
      output, status = Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, "invalid json{")
      
      expect(status.success?).to be true  # Script should handle error gracefully
      expect(output).to include("Invalid input")
    end
    
    it "handles invalid cell type" do
      # Create notebook
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      # Try to add cell with invalid type
      cells = [{ type: "invalid_type", content: "Test" }]
      
      output, status = Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      expect(status.success?).to be true
      expect(output).to include("Invalid cell type")
    end
    
    it "handles out of range cell index" do
      # Create notebook with one cell
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      cells = [{ type: "markdown", content: "# Only Cell" }]
      Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      # Try to delete non-existent cell
      output, status = Open3.capture2("python3", jupyter_controller_path, "delete", notebook_filename, "5")
      
      expect(status.success?).to be true
      expect(output).to include("out of range")
    end
  end
  
  describe "Display Functionality" do
    it "displays notebook contents" do
      # Create and populate notebook
      output, _ = Open3.capture2("python3", jupyter_controller_path, "create", test_notebook_name)
      match = output.match(/Notebook created: (.+\.ipynb)/)
      notebook_filename = match[1].gsub(".ipynb", "")
      
      cells = [
        { type: "markdown", content: "# Display Test" },
        { type: "code", content: "x = 42\nprint(x)" }
      ]
      
      Open3.capture2("python3", jupyter_controller_path, "add", notebook_filename, cells.to_json)
      
      # Display notebook
      output, status = Open3.capture2("python3", jupyter_controller_path, "display", notebook_filename)
      
      expect(status.success?).to be true
      expect(output).to include("Cell 0 - Type: markdown")
      expect(output).to include("# Display Test")
      expect(output).to include("Cell 1 - Type: code")
      expect(output).to include("x = 42")
    end
  end
end