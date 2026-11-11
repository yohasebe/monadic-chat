# frozen_string_literal: true

require "shellwords"
require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/jupyter_operations"
require_relative "../../../apps/auto_forge/auto_forge_tools"

# What a tool makes is shown in the work screen for the reply (a notebook a
# Jupyter tool made or changed, the screenshot AutoForge's debug took); the
# result tells the model so, and is as it was when it cannot be shown.
RSpec.describe "Tools that show what they made in the work screen" do
  let(:workbench) { Object.new }
  let(:shown) { [] }
  let(:said) { JSON.generate("status" => "shown_in_work_screen") }

  before do
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file) do |path, caller|
      shown << [path, caller]
      said
    end
  end

  describe "the Jupyter tools" do
    # The tools as the apps have them, with the Python container's answers.
    let(:app) do
      Class.new do
        include MonadicSharedTools::JupyterOperations

        def send_command(command:, container:)
          raise "not the Python container" unless container == "python"

          if command.start_with?("jupyter_controller.py create ")
            "Notebook created: #{Shellwords.split(command).last}_20260101_000000.ipynb"
          else
            "Cell updated."
          end
        end
      end.new
    end

    it "shows a new notebook by the name it was made with, keeps its JupyterLab address, and says so" do
      result = app.create_jupyter_notebook(filename: "analysis", workbench: workbench)
      expect(shown).to eq([["analysis_20260101_000000.ipynb", workbench]])
      expect(result).to include("/lab/tree/analysis_20260101_000000.ipynb")
      expect(result).to end_with("The notebook is shown in the work screen beside the chat.")
    end

    it "shows the notebook again once its cells change" do
      app.update_jupyter_cell(filename: "nb_20260101_000000", index: 0, content: "x", workbench: workbench)
      app.delete_jupyter_cell(filename: "nb.ipynb", index: 1, workbench: workbench)
      expect(shown.map(&:first)).to eq(["nb_20260101_000000.ipynb", "nb.ipynb"])
    end

    it "shows nothing for a tool that only reads" do
      app.get_jupyter_cells_with_results(filename: "nb")
      expect(shown).to be_empty
    end

    it "leaves the result as it was with no reply to show it for, or when it could not be shown" do
      expect(app.update_jupyter_cell(filename: "nb", index: 0, content: "x")).to eq("Cell updated.")
      expect(shown).to be_empty

      allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return("❌ The file was not shown in the work screen: full.")
      expect(app.update_jupyter_cell(filename: "nb", index: 0, content: "x", workbench: workbench)).to eq("Cell updated.")
    end

    it "takes the caller from the server (an argument the model cannot give)" do
      %i[create_jupyter_notebook add_jupyter_cells update_jupyter_cell delete_jupyter_cell
         insert_jupyter_cells move_jupyter_cell execute_and_fix_jupyter_cells
         create_and_populate_jupyter_notebook].each do |name|
        expect(app.method(name).parameters).to include([:key, :workbench])
      end
    end
  end

  describe "AutoForge's debug" do
    let(:tool) { Class.new { include AutoForgeTools }.new }
    let(:debugger) { double("debugger") }
    let(:report) do
      { success: true, screenshot: "auto_forge/App_1/debug.png", javascript_errors: [], warnings: [],
        summary: ["✅ Page loaded successfully"], performance: {}, functionality_tests: [] }
    end

    before do
      tool.instance_variable_set(:@context, {})
      allow(tool).to receive(:resolve_project_context).and_return(success: true, project_name: "App", html_path: "/x/index.html")
      allow(AutoForge::Debugger).to receive(:new).and_return(debugger)
      allow(debugger).to receive(:check_selenium_or_error).and_return(nil)
      allow(debugger).to receive(:debug_html).and_return(report)
    end

    it "shows the screenshot in the work screen and names it, with no image in the chat" do
      result = tool.debug_application({ "spec" => { "name" => "App" } }, workbench: workbench)
      expect(result).to be_a(String)
      expect(shown).to eq([["auto_forge/App_1/debug.png", workbench]])
      expect(result).to include("Screenshot: auto_forge/App_1/debug.png")
      expect(result).to include("shown in the work screen beside the chat")
    end

    it "takes its arguments as keywords too" do
      result = tool.debug_application(spec: { name: "App" }, workbench: workbench)
      expect(result).to include("Screenshot: auto_forge/App_1/debug.png")
      expect(tool).to have_received(:resolve_project_context).with({ spec: { name: "App" } })
    end

    it "says why the screenshot is not in the work screen when it cannot be shown" do
      allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return("❌ The file was not shown in the work screen: full.")
      result = tool.debug_application(spec: { name: "App" })
      expect(result).to include("❌ The file was not shown in the work screen")
    end
  end
end
