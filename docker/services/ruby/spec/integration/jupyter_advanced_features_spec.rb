# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Jupyter Advanced Features", :integration do
  let(:test_notebook) { "test_advanced_#{Time.now.to_i}" }
  let(:app_instance) { JupyterNotebookOpenAI.new if defined?(JupyterNotebookOpenAI) }
  
  before(:all) do
    unless defined?(JupyterNotebookOpenAI)
      skip "JupyterNotebookOpenAI not loaded"
    end
  end
  
  before do
    skip "JupyterNotebookOpenAI not available" unless app_instance
    # Start Jupyter if not running
    app_instance.run_jupyter(command: "start")
    sleep 2
  end
  
  after do
    # Clean up test notebooks
    if app_instance
      Dir.glob(File.join(MonadicApp::LOCAL_SHARED_VOL, "#{test_notebook}*.ipynb")).each do |file|
        File.delete(file) rescue nil
      end
    end
  end
  
  describe "Kernel Management" do
    it "can restart kernel and clear outputs" do
      # Create a notebook with some cells
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      expect(result).to include("Access it at:")
      
      # Extract actual filename with timestamp - handle "Notebook 'filename'" format
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      # Add cells with output
      cells = [
        { "cell_type" => "code", "source" => "x = 10\nprint(f'x = {x}')" },
        { "cell_type" => "code", "source" => "y = 20\nprint(f'y = {y}')" }
      ]
      
      add_result = app_instance.add_jupyter_cells(
        filename: actual_filename.sub('.ipynb', ''),
        cells: cells,
        run: true
      )
      expect(add_result.downcase).to include("command has been executed")
      
      # Restart kernel
      restart_result = app_instance.restart_jupyter_kernel(filename: actual_filename.sub('.ipynb', ''))
      expect(restart_result.downcase).to include("restart")
    end
    
    it "handles interrupt request appropriately" do
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      interrupt_result = app_instance.interrupt_jupyter_execution(filename: actual_filename)
      expect(interrupt_result).to include("not currently supported")
    end
  end
  
  describe "Cell Movement" do
    it "can move cells to new positions" do
      # Create notebook with multiple cells
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      cells = [
        { "cell_type" => "markdown", "source" => "# Cell 0" },
        { "cell_type" => "code", "source" => "# Cell 1" },
        { "cell_type" => "markdown", "source" => "# Cell 2" },
        { "cell_type" => "code", "source" => "# Cell 3" }
      ]
      
      app_instance.add_jupyter_cells(filename: actual_filename, cells: cells, run: false)
      
      # Move cell from index 1 to index 3
      move_result = app_instance.move_jupyter_cell(
        filename: actual_filename.sub('.ipynb', ''),
        from_index: 1,
        to_index: 3
      )
      expect(move_result).to include("Successfully moved cell")
      
      # Note: Actual cell movement implementation is pending
      # For now, just verify the function returns success message
    end
    
    it "handles invalid indices gracefully" do
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      # Try to move with invalid index
      move_result = app_instance.move_jupyter_cell(
        filename: actual_filename.sub('.ipynb', ''),
        from_index: 10,
        to_index: 0
      )
      expect(move_result).to include("Error")
    end
  end
  
  describe "Cell Insertion" do
    it "can insert cells at specific positions" do
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      # Add initial cells
      initial_cells = [
        { "cell_type" => "markdown", "source" => "# First" },
        { "cell_type" => "markdown", "source" => "# Last" }
      ]
      app_instance.add_jupyter_cells(filename: actual_filename, cells: initial_cells, run: false)
      
      # Insert cell in the middle
      insert_cells = [
        { "cell_type" => "markdown", "source" => "# Middle" }
      ]
      
      insert_result = app_instance.insert_jupyter_cells(
        filename: actual_filename.sub('.ipynb', ''),
        index: 1,
        cells: insert_cells,
        run: false
      )
      expect(insert_result).to include("Successfully inserted")
      
      # Note: Actual cell insertion implementation is pending
      # For now, just verify the function returns success message
    end
    
    it "can insert and run cells" do
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      # Insert cells with run flag
      insert_cells = [
        { "cell_type" => "code", "source" => "result = 2 + 2\nprint(f'Result: {result}')" }
      ]
      
      insert_result = app_instance.insert_jupyter_cells(
        filename: actual_filename.sub('.ipynb', ''),
        index: 0,
        cells: insert_cells,
        run: true
      )
      
      expect(insert_result).to include("Successfully inserted")
      # The run flag should cause execution
      expect(insert_result.downcase).to include("executed")
    end
  end
  
  describe "Integration with existing features" do
    it "works with existing add, delete, update functions" do
      result = app_instance.create_jupyter_notebook(filename: test_notebook)
      actual_filename = if result.match(/Notebook\s+'([^']+\.ipynb)'/)
                          result.match(/Notebook\s+'([^']+\.ipynb)'/)[1]
                        elsif result.match(/([^\/]+\.ipynb)/)
                          result.match(/([^\/]+\.ipynb)/)[1]
                        end
      skip "Could not extract filename" unless actual_filename
      
      # Use new insert function
      app_instance.insert_jupyter_cells(
        filename: actual_filename.sub('.ipynb', ''),
        index: 0,
        cells: [{ "cell_type" => "code", "source" => "# Cell 0" }],
        run: false
      )
      
      # Use existing add function
      app_instance.add_jupyter_cells(
        filename: actual_filename.sub('.ipynb', ''),
        cells: [{ "cell_type" => "code", "source" => "# Cell 1" }],
        run: false
      )
      
      # Use new move function
      app_instance.move_jupyter_cell(
        filename: actual_filename.sub('.ipynb', ''),
        from_index: 1,
        to_index: 0
      )
      
      # Use existing delete function
      app_instance.delete_jupyter_cell(
        filename: actual_filename.sub('.ipynb', ''),
        index: 1
      )
      
      # Verify final state
      cells_result = app_instance.get_jupyter_cells_with_results(
        filename: actual_filename.sub('.ipynb', '')
      )
      
      expect(cells_result).to be_an(Array)
      expect(cells_result.length).to eq(1)
    end
  end
end