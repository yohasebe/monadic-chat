# frozen_string_literal: true

# Jupyter Notebook Operations Integration Test
#
# Tests the core notebook operations across all providers:
# - Notebook creation with link display
# - Cell addition with link display
# - Cell deletion
# - Cell update
#
# Run with:
#   RUN_API=true bundle exec rspec spec/integration/jupyter_notebook_operations_spec.rb
#
# Run with specific provider:
#   PROVIDERS=gemini RUN_API=true bundle exec rspec spec/integration/jupyter_notebook_operations_spec.rb

require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "Jupyter Notebook Operations", :integration, :api do
  before(:all) do
    skip "RUN_API not enabled (set RUN_API=true to run these tests)" unless ENV["RUN_API"]
  end
  # Test data directory
  let(:data_path) { File.join(Dir.home, "monadic", "data") }
  let(:test_notebook_prefix) { "test_operations" }

  # Cleanup helper
  def cleanup_test_notebooks
    Dir.glob(File.join(data_path, "#{test_notebook_prefix}*.ipynb")).each do |f|
      File.delete(f) if File.exist?(f)
    end
  end

  before(:all) do
    # Load required app files
    require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"

    # Load all provider-specific MDSL files
    %w[openai claude gemini grok].each do |provider|
      mdsl_path = File.expand_path("../../apps/jupyter_notebook/jupyter_notebook_#{provider}.mdsl", __dir__)
      load mdsl_path if File.exist?(mdsl_path)
    end
  end

  before(:each) do
    cleanup_test_notebooks
  end

  after(:each) do
    cleanup_test_notebooks
  end

  # Provider configurations for testing
  JUPYTER_PROVIDERS = {
    "gemini" => {
      class_name: "JupyterNotebookGemini",
      api_key_env: "GEMINI_API_KEY",
      has_combined_function: true
    },
    "openai" => {
      class_name: "JupyterNotebookOpenAI",
      api_key_env: "OPENAI_API_KEY",
      has_combined_function: false
    },
    "claude" => {
      class_name: "JupyterNotebookClaude",
      api_key_env: "ANTHROPIC_API_KEY",
      has_combined_function: false
    },
    "grok" => {
      class_name: "JupyterNotebookGrok",
      api_key_env: "XAI_API_KEY",
      has_combined_function: true
    }
  }.freeze

  describe "Basic Notebook Operations" do
    JUPYTER_PROVIDERS.each do |provider_name, config|
      context "with #{provider_name.capitalize} provider" do
        let(:app_class) { Object.const_get(config[:class_name]) }
        let(:app_instance) do
          instance = app_class.new
          class_settings = app_class.instance_variable_get(:@settings)
          instance.settings = class_settings if class_settings
          instance
        end

        before do
          skip "#{config[:api_key_env]} not configured" unless ENV[config[:api_key_env]]
        end

        describe "#run_jupyter" do
          it "can start JupyterLab server" do
            result = app_instance.run_jupyter(command: "start")

            expect(result).to be_a(String)
            expect(result).to match(/jupyter|running|started/i)
          end

          it "can stop JupyterLab server" do
            # Start first to ensure it's running
            app_instance.run_jupyter(command: "start")
            sleep 1

            result = app_instance.run_jupyter(command: "stop")

            expect(result).to be_a(String)
            expect(result).to match(/jupyter|stopped/i)
          end
        end

        describe "#create_jupyter_notebook" do
          before do
            app_instance.run_jupyter(command: "start")
            sleep 2
          end

          it "creates a notebook and returns a link" do
            filename = "#{test_notebook_prefix}_create_#{provider_name}"
            result = app_instance.create_jupyter_notebook(filename: filename)

            expect(result).to be_a(String)
            expect(result).to match(/created|success/i)
            expect(result).to include(".ipynb")

            # Verify link format
            expect(result).to match(%r{http://.*:8889/lab/tree/.*\.ipynb})
          end

          it "creates notebook file on disk" do
            filename = "#{test_notebook_prefix}_disk_#{provider_name}"
            app_instance.create_jupyter_notebook(filename: filename)

            # Find the created file (may have timestamp appended)
            files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
            expect(files).not_to be_empty

            # Verify it's valid JSON notebook format
            notebook_content = JSON.parse(File.read(files.first))
            expect(notebook_content).to have_key("cells")
            expect(notebook_content).to have_key("metadata")
          end
        end

        describe "#add_jupyter_cells" do
          before do
            app_instance.run_jupyter(command: "start")
            sleep 2
          end

          let(:test_cells) do
            [
              { "cell_type" => "markdown", "source" => "# Test Notebook\n\nCreated by #{provider_name}" },
              { "cell_type" => "code", "source" => "print('Hello from #{provider_name}')" }
            ]
          end

          it "adds cells to notebook and returns a link" do
            # Create notebook first
            filename = "#{test_notebook_prefix}_cells_#{provider_name}"
            create_result = app_instance.create_jupyter_notebook(filename: filename)

            # Extract actual filename with timestamp
            actual_filename = if create_result =~ /['"]([^'"]+\.ipynb)['"]/
                                $1
                              else
                                "#{filename}.ipynb"
                              end

            # Add cells
            result = app_instance.add_jupyter_cells(
              filename: actual_filename.sub(".ipynb", ""),
              cells: test_cells,
              run: false
            )

            expect(result).to be_a(String)
            expect(result).to match(/added|success|cells/i)

            # Verify link format
            expect(result).to match(%r{http://.*:8889/lab/tree/.*\.ipynb})
          end

          it "actually adds cells to the notebook file" do
            filename = "#{test_notebook_prefix}_verify_cells_#{provider_name}"
            create_result = app_instance.create_jupyter_notebook(filename: filename)

            # Find created file
            files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
            expect(files).not_to be_empty
            actual_file = files.first

            # Add cells
            app_instance.add_jupyter_cells(
              filename: File.basename(actual_file, ".ipynb"),
              cells: test_cells,
              run: false
            )

            # Verify cells were added
            notebook_content = JSON.parse(File.read(actual_file))
            # Should have font config cell (auto-injected) + our 2 cells
            expect(notebook_content["cells"].length).to be >= 2

            # Check for our markdown content
            markdown_cell = notebook_content["cells"].find { |c| c["cell_type"] == "markdown" }
            expect(markdown_cell).not_to be_nil
          end
        end

        describe "#delete_jupyter_cell" do
          before do
            app_instance.run_jupyter(command: "start")
            sleep 2
          end

          it "can delete a cell from notebook" do
            # Create notebook with cells
            filename = "#{test_notebook_prefix}_delete_#{provider_name}"
            app_instance.create_jupyter_notebook(filename: filename)

            files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
            expect(files).not_to be_empty
            actual_file = files.first
            actual_filename = File.basename(actual_file, ".ipynb")

            # Add cells
            test_cells = [
              { "cell_type" => "code", "source" => "print('Cell 1')" },
              { "cell_type" => "code", "source" => "print('Cell 2')" }
            ]
            app_instance.add_jupyter_cells(filename: actual_filename, cells: test_cells, run: false)

            # Get initial cell count
            notebook_before = JSON.parse(File.read(actual_file))
            cell_count_before = notebook_before["cells"].length

            # Delete a cell
            result = app_instance.delete_jupyter_cell(filename: actual_filename, index: 1)

            expect(result).to be_a(String)
            expect(result).to match(/deleted|removed|success/i)

            # Verify cell was deleted
            notebook_after = JSON.parse(File.read(actual_file))
            expect(notebook_after["cells"].length).to eq(cell_count_before - 1)
          end
        end

        describe "#get_jupyter_cells_with_results" do
          before do
            app_instance.run_jupyter(command: "start")
            sleep 2
          end

          it "returns cell contents from notebook" do
            filename = "#{test_notebook_prefix}_get_#{provider_name}"
            app_instance.create_jupyter_notebook(filename: filename)

            files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
            actual_filename = File.basename(files.first, ".ipynb")

            test_cells = [{ "cell_type" => "code", "source" => "x = 42" }]
            app_instance.add_jupyter_cells(filename: actual_filename, cells: test_cells, run: false)

            result = app_instance.get_jupyter_cells_with_results(filename: actual_filename)

            # Result can be Array (of cell hashes) or String (JSON or error)
            if result.is_a?(Array)
              expect(result).not_to be_empty
              expect(result.first).to have_key(:source).or have_key("source")
            else
              expect(result).to be_a(String)
              expect(result.length).to be > 0
            end
          end
        end

        if config[:has_combined_function]
          describe "#create_and_populate_jupyter_notebook" do
            before do
              app_instance.run_jupyter(command: "start")
              sleep 2
            end

            it "creates notebook with cells in one operation" do
              filename = "#{test_notebook_prefix}_combined_#{provider_name}"
              cells = [
                { "cell_type" => "markdown", "source" => "# Combined Test" },
                { "cell_type" => "code", "source" => "print('Combined function test')" }
              ]

              result = app_instance.create_and_populate_jupyter_notebook(
                filename: filename,
                cells: cells
              )

              expect(result).to be_a(String)
              expect(result).to match(/created|success/i)
              expect(result).to match(%r{http://.*:8889/lab/tree/.*\.ipynb})

              # Verify file was created with cells
              files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
              expect(files).not_to be_empty

              notebook_content = JSON.parse(File.read(files.first))
              expect(notebook_content["cells"].length).to be >= 2
            end
          end
        end
      end
    end
  end

  describe "Link Display Verification" do
    # This test verifies that notebook operations return URLs for linking
    # The HTML formatting is done by the LLM, so we verify URL presence

    let(:app_instance) do
      # Use Gemini as reference implementation
      skip "GEMINI_API_KEY not configured" unless ENV["GEMINI_API_KEY"]

      require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"
      mdsl_path = File.expand_path("../../apps/jupyter_notebook/jupyter_notebook_gemini.mdsl", __dir__)
      load mdsl_path if File.exist?(mdsl_path)

      instance = JupyterNotebookGemini.new
      class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
      instance.settings = class_settings if class_settings
      instance
    end

    before do
      app_instance.run_jupyter(command: "start")
      sleep 2
    end

    it "notebook creation returns URL link" do
      filename = "#{test_notebook_prefix}_link_test"
      result = app_instance.create_jupyter_notebook(filename: filename)

      # Should contain URL to the notebook
      expect(result).to match(%r{http://.*:8889/lab/tree/.*\.ipynb})
    end

    it "cell addition returns URL link" do
      filename = "#{test_notebook_prefix}_link_cells"
      app_instance.create_jupyter_notebook(filename: filename)

      files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
      actual_filename = File.basename(files.first, ".ipynb")

      result = app_instance.add_jupyter_cells(
        filename: actual_filename,
        cells: [{ "cell_type" => "code", "source" => "x = 1" }],
        run: false
      )

      # Should contain URL to the notebook
      expect(result).to match(%r{http://.*:8889/lab/tree/.*\.ipynb})
    end
  end

  describe "Error Handling" do
    let(:app_instance) do
      skip "GEMINI_API_KEY not configured" unless ENV["GEMINI_API_KEY"]

      require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"
      mdsl_path = File.expand_path("../../apps/jupyter_notebook/jupyter_notebook_gemini.mdsl", __dir__)
      load mdsl_path if File.exist?(mdsl_path)

      instance = JupyterNotebookGemini.new
      class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
      instance.settings = class_settings if class_settings
      instance
    end

    it "handles invalid filename gracefully" do
      result = app_instance.create_jupyter_notebook(filename: "")

      # Can return Hash with error key or String with error message
      if result.is_a?(Hash)
        expect(result[:error] || result["error"]).to match(/error|invalid|required|empty/i)
      else
        expect(result.to_s).to match(/error|invalid|required/i)
      end
    end

    it "handles non-existent notebook for cell operations" do
      result = app_instance.add_jupyter_cells(
        filename: "nonexistent_notebook_12345",
        cells: [{ "cell_type" => "code", "source" => "x = 1" }]
      )

      # Should return String with warning or error message
      expect(result).to be_a(String)
      expect(result).to match(/not exist|not found|warning|error|fail/i)
    end

    it "handles invalid cell index for deletion" do
      app_instance.run_jupyter(command: "start")
      sleep 2

      filename = "#{test_notebook_prefix}_error_delete"
      app_instance.create_jupyter_notebook(filename: filename)

      files = Dir.glob(File.join(data_path, "#{filename}*.ipynb"))
      actual_filename = File.basename(files.first, ".ipynb")

      # Try to delete cell at invalid index
      result = app_instance.delete_jupyter_cell(filename: actual_filename, index: 999)

      # Should handle gracefully - can be String or Hash
      expect(result).to be_a(String).or be_a(Hash)
    end
  end
end
