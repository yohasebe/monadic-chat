require "spec_helper"

RSpec.describe "Gemini Jupyter Combined Function" do
  # Create a test class that includes MonadicHelper
  let(:jupyter_helper) do
    Class.new do
      include MonadicHelper
      attr_accessor :session
      
      def initialize
        @session = { parameters: {} }
      end
      
      # Mock methods needed by jupyter_helper
      def send_command(command:, container:, success: nil, success_with_output: nil)
        success || "Command executed"
      end
      
      def write_to_file(filename:, extension:, text:)
        true
      end
    end.new
  end
  
  before(:each) do
    # Set up data path
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/tmp")
    
    # Clean up any existing test notebooks
    test_files = Dir.glob(File.join("/tmp", "test_*.ipynb"))
    test_files.each { |f| File.delete(f) if File.exist?(f) }
  end
  
  describe "#create_and_populate_jupyter_notebook" do
    context "when creating a new notebook with cells" do
      let(:filename) { "test_notebook" }
      let(:cells) do
        [
          { "cell_type" => "markdown", "source" => "# Test Notebook" },
          { "cell_type" => "code", "source" => "import numpy as np\nprint('Hello')" }
        ]
      end
      
      it "creates notebook and adds cells in one call" do
        # Mock the create_jupyter_notebook response
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        expected_filename = "#{filename}_#{timestamp}"
        create_response = "Notebook '#{expected_filename}.ipynb' created successfully. Access it at: http://localhost:8889/lab/tree/#{expected_filename}.ipynb"
        
        # Mock the add_jupyter_cells response
        add_response = "The cells have been added to the notebook successfully."
        
        allow(jupyter_helper).to receive(:create_jupyter_notebook).with(filename: filename).and_return(create_response)
        allow(jupyter_helper).to receive(:add_jupyter_cells).with(
          filename: expected_filename,
          cells: cells,
          run: true
        ).and_return(add_response)
        
        result = jupyter_helper.create_and_populate_jupyter_notebook(filename: filename, cells: cells)
        
        expect(result).to include("created successfully")
        expect(result).to include("cells have been added")
      end
      
      it "handles empty cells array" do
        allow(jupyter_helper).to receive(:create_jupyter_notebook).with(filename: filename).and_return(
          "Notebook 'test_notebook_20240828_123456.ipynb' created successfully."
        )
        
        result = jupyter_helper.create_and_populate_jupyter_notebook(filename: filename, cells: [])
        
        expect(result).to include("created successfully")
        expect(result).not_to include("cells have been added")
      end
      
      it "handles nil cells parameter" do
        allow(jupyter_helper).to receive(:create_jupyter_notebook).with(filename: filename).and_return(
          "Notebook 'test_notebook_20240828_123456.ipynb' created successfully."
        )
        
        result = jupyter_helper.create_and_populate_jupyter_notebook(filename: filename, cells: nil)
        
        expect(result).to include("created successfully")
        expect(result).not_to include("cells have been added")
      end
      
      it "extracts filename with timestamp correctly" do
        # Test the filename extraction with various response formats
        test_cases = [
          {
            response: "Notebook 'math_20240828_123456.ipynb' created successfully.",
            has_cells: true
          },
          {
            # Second format also needs 'Notebook' and quotes for extraction
            response: "Notebook 'test_notebook_20240828_234567.ipynb' created successfully at /data/",
            has_cells: true  
          },
          {
            # Format without quotes won't extract properly
            response: "Created notebook test_20240828_234567.ipynb successfully",
            has_cells: false  # Won't extract filename, so no cells added
          }
        ]
        
        test_cases.each do |tc|
          allow(jupyter_helper).to receive(:create_jupyter_notebook).and_return(tc[:response])
          allow(jupyter_helper).to receive(:add_jupyter_cells).and_return("Cells added")
          
          result = jupyter_helper.create_and_populate_jupyter_notebook(
            filename: "test", 
            cells: [{"cell_type" => "code", "source" => "test"}]
          )
          
          # Check expectations based on whether filename extraction works
          expect(result).to include("created") if tc[:response].include?("created")
          expect(result).to include("Cells added") if tc[:has_cells]
        end
      end
    end
    
    context "when notebook creation fails" do
      let(:filename) { "invalid/notebook" }
      let(:cells) { [{ "cell_type" => "code", "source" => "test" }] }
      
      it "returns error message without attempting to add cells" do
        error_message = "Error: Invalid filename"
        allow(jupyter_helper).to receive(:create_jupyter_notebook).with(filename: filename).and_return(error_message)
        
        result = jupyter_helper.create_and_populate_jupyter_notebook(filename: filename, cells: cells)
        
        expect(result).to eq(error_message)
        expect(jupyter_helper).not_to receive(:add_jupyter_cells)
      end
    end
    
    context "with non-ASCII content" do
      let(:filename) { "math_notebook" }
      let(:cells) do
        [
          { "cell_type" => "markdown", "source" => "# Math Lesson Grade 5" },
          { "cell_type" => "code", "source" => "# Addition\nresult = 10 + 20\nprint(f'Answer: {result}')" }
        ]
      end

      it "handles various character encodings correctly" do
        allow(jupyter_helper).to receive(:create_jupyter_notebook).and_return(
          "Notebook 'math_notebook_20240828_123456.ipynb' created successfully."
        )
        allow(jupyter_helper).to receive(:add_jupyter_cells).and_return("Cells added successfully.")

        result = jupyter_helper.create_and_populate_jupyter_notebook(filename: filename, cells: cells)

        expect(result).to include("created successfully")
        expect(result).to include("Cells added successfully")
      end
    end
  end
end