# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "shellwords"
require "json"
require_relative "../../../lib/monadic/adapters/jupyter_helper"

RSpec.describe "JupyterHelper" do
  let(:test_class) do
    Class.new do
      include MonadicHelper

      def send_command(command:, container:, success: nil)
        @last_command = command
        @last_container = container
        success || "Mock response"
      end

      attr_reader :last_command, :last_container
    end
  end

  let(:helper) { test_class.new }

  describe "#create_jupyter_notebook" do
    before do
      allow(helper).to receive(:send_command).and_return("Notebook created: test_notebook.ipynb")
      allow(helper).to receive(:get_jupyter_base_url).and_return("http://127.0.0.1:8889")
    end

    it "creates a new Jupyter notebook" do
      result = helper.create_jupyter_notebook(filename: "my_notebook")
      expect(result).to include("test_notebook.ipynb")
    end

    it "strips .ipynb extension from filename" do
      allow(helper).to receive(:send_command) do |args|
        expect(args[:command]).to include("create my_notebook")
        "Notebook created: my_notebook_20241001_120000.ipynb"
      end
      helper.create_jupyter_notebook(filename: "my_notebook.ipynb")
    end
  end

  describe "#delete_jupyter_cell" do
    it "returns error when filename is empty" do
      result = helper.delete_jupyter_cell(filename: "", index: 0)
      expect(result).to eq("Error: Filename is required.")
    end

    it "sends delete command to Python container" do
      allow(helper).to receive(:send_command).and_return("Cell deleted")
      result = helper.delete_jupyter_cell(filename: "test.ipynb", index: 2)
      expect(helper).to have_received(:send_command).with(
        hash_including(command: include("delete"), container: "python")
      )
    end
  end

  describe "#update_jupyter_cell" do
    it "returns error when filename is empty" do
      result = helper.update_jupyter_cell(filename: "", content: "code")
      expect(result).to eq("Error: Filename is required.")
    end

    it "returns error when content is empty" do
      result = helper.update_jupyter_cell(filename: "test.ipynb", content: "")
      expect(result).to eq("Error: Content is required.")
    end

    it "sends update command to Python container" do
      allow(helper).to receive(:send_command).and_return("Cell updated")
      helper.update_jupyter_cell(filename: "test.ipynb", index: 0, content: "print('hello')")
      expect(helper).to have_received(:send_command).with(
        hash_including(command: include("update"), container: "python")
      )
    end
  end

  describe "#get_jupyter_cells_with_results" do
    it "returns error when filename is empty" do
      result = helper.get_jupyter_cells_with_results(filename: "")
      expect(result).to eq("Error: Filename is required.")
    end

    context "when notebook exists" do
      let(:notebook_content) do
        {
          "cells" => [
            { "cell_type" => "code", "source" => ["print('hello')"], "outputs" => [] },
            { "cell_type" => "markdown", "source" => ["# Title"] }
          ]
        }.to_json
      end

      before do
        allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
        # Notebooks are read through the guard
        allow(Monadic::Utils::SharedPathGuard).to receive(:read_bytes!).and_return(notebook_content)
      end

      it "returns cells with their info" do
        result = helper.get_jupyter_cells_with_results(filename: "test.ipynb")
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result[0][:type]).to eq("code")
        expect(result[1][:type]).to eq("markdown")
      end

      it "handles filename without .ipynb extension" do
        helper.get_jupyter_cells_with_results(filename: "test")
        expect(Monadic::Utils::SharedPathGuard).to have_received(:read_bytes!).with("/test/data/test.ipynb")
      end
    end

    context "when notebook does not exist" do
      around do |example|
        Dir.mktmpdir("jupyter-none") do |dir|
          @empty = dir
          example.run
        end
      end

      before { allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@empty) }

      it "returns error message" do
        result = helper.get_jupyter_cells_with_results(filename: "nonexistent.ipynb")
        expect(result).to eq("Error: Notebook not found.")
      end
    end
  end

  describe "#execute_and_fix_jupyter_cells" do
    it "returns error when filename is empty" do
      result = helper.execute_and_fix_jupyter_cells(filename: "")
      expect(result).to eq("Error: Filename is required.")
    end
  end

  # The notebook commands run in the Python container; here, what the
  # container answers is given, and what was asked of it is kept.
  describe "notebook commands" do
    around do |example|
      Dir.mktmpdir('notebook-shared-') do |directory|
        @data_dir = File.realpath(directory)
        File.write(File.join(@data_dir, 'test.ipynb'), JSON.generate('cells' => []))
        example.run
      end
    end

    let(:asked) { [] }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data_dir)
    end

    def answer(*replies)
      allow(helper).to receive(:send_command) do |command:, timeout: nil, **_, &block|
        asked << { command: command, timeout: timeout }
        out, err, ok = replies.length > 1 ? replies.shift : replies.first
        block.call(out, err, instance_double(Process::Status, success?: ok))
      end
    end

    def argv(index = -1)
      Shellwords.split(asked[index][:command])
    end

    def notebook_with(cells)
      File.write(File.join(@data_dir, 'test.ipynb'), JSON.generate('cells' => cells))
    end

    describe "#move_jupyter_cell" do
      it "moves a cell at any position, by the container's own command" do
        answer(["Moved cell 12 to position 3\n", "", true])
        expect(helper.move_jupyter_cell(filename: "test", from_index: 12, to_index: "3")).to eq("Moved cell 12 to position 3.")
        expect(argv).to eq(%w[jupyter_controller.py move test.ipynb 12 3])
      end

      it "says why the cell was not moved" do
        answer(["", "Error: to_index 40 is out of range: the notebook has 12 cells (0 to 11)\n", false])
        expect(helper.move_jupyter_cell(filename: "test.ipynb", from_index: 0, to_index: 40))
          .to eq("Error: The cell was not moved. Error: to_index 40 is out of range: the notebook has 12 cells (0 to 11)")
      end

      it "asks nothing of the container for a missing notebook or positions that are not whole numbers from 0" do
        answer(["", "", true])
        expect(helper.move_jupyter_cell(filename: "", from_index: 0, to_index: 1)).to start_with("Error:")
        expect(helper.move_jupyter_cell(filename: "missing.ipynb", from_index: 0, to_index: 1)).to start_with("Error:")
        expect(helper.move_jupyter_cell(filename: "../test.ipynb", from_index: 0, to_index: 1)).to start_with("Error:")
        [[-1, 0], [0, -1], ["one", 0], [0, 1.5]].each do |from, to|
          expect(helper.move_jupyter_cell(filename: "test.ipynb", from_index: from, to_index: to)).to start_with("Error:")
        end
        expect(asked).to be_empty
      end
    end

    describe "#insert_jupyter_cells" do
      it "inserts the cells as the container's notebook expects them" do
        answer(["Inserted 1 cell(s) at position 0\n", "", true])
        result = helper.insert_jupyter_cells(filename: "test.ipynb", index: 0, cells: [{ "type" => "code", "content" => "x = '$(id)'" }])
        expect(result).to eq("Inserted 1 cell(s) at position 0.")
        expect(argv[0..3]).to eq(%w[jupyter_controller.py insert test.ipynb 0])
        expect(JSON.parse(argv[4])).to eq([{ "cell_type" => "code", "source" => "x = '$(id)'" }])
      end

      it "runs the whole notebook afterwards when asked, and says what the run found" do
        notebook_with([{ "cell_type" => "code", "source" => "1/0",
                         "outputs" => [{ "output_type" => "error", "ename" => "ZeroDivisionError", "evalue" => "division by zero", "traceback" => [] }] }])
        answer(["Inserted 1 cell(s) at position 1\n", "", true], ["", "", true])
        result = helper.insert_jupyter_cells(filename: "test.ipynb", index: 1, cells: [{ "type" => "code", "content" => "y" }], run: true)
        expect(argv(1)).to include("--execute")
        expect(result).to start_with("Inserted 1 cell(s) at position 1.")
        expect(result).to include("Cell 0 (ZeroDivisionError)")
      end

      it "runs nothing when the cells were not inserted" do
        answer(["", "Error: index 9 is out of range: the notebook has 0 cells (0 to 0)\n", false])
        result = helper.insert_jupyter_cells(filename: "test.ipynb", index: 9, cells: [{ "type" => "code", "content" => "y" }], run: true)
        expect(result).to start_with("Error: The cells were not inserted.")
        expect(asked.length).to eq(1)
      end

      it "asks nothing of the container for no cells, a bad position or cells too large for one call" do
        answer(["", "", true])
        expect(helper.insert_jupyter_cells(filename: "test.ipynb", index: 0, cells: [])).to start_with("Error:")
        expect(helper.insert_jupyter_cells(filename: "test.ipynb", index: -1, cells: [{ "type" => "code" }])).to start_with("Error:")
        big = [{ "type" => "code", "content" => "x" * MonadicHelper::INSERT_LIMIT }]
        expect(helper.insert_jupyter_cells(filename: "test.ipynb", index: 0, cells: big)).to include("too large")
        expect(asked).to be_empty
      end
    end

    describe "#run_jupyter_cells" do
      it "gives a run longer than any one cell may take" do
        answer(["", "", true])
        helper.run_jupyter_cells(filename: "test")
        expect(asked.last[:timeout]).to be > MonadicHelper::JUPYTER_RUN_TIMEOUT
      end

      it "says a run that failed, ran out of time or was stopped did not finish" do
        answer(["", "Timed out", false])
        expect(helper.run_jupyter_cells(filename: "test.ipynb")).to eq("Error: The notebook could not be run to the end. Timed out")
      end

      it "says which cells raised errors in a run that finished" do
        notebook_with([{ "cell_type" => "code", "source" => "ok", "outputs" => [] },
                       { "cell_type" => "code", "source" => "boom",
                         "outputs" => [{ "output_type" => "error", "ename" => "NameError", "evalue" => "boom", "traceback" => [] }] }])
        answer(["", "", true])
        result = helper.run_jupyter_cells(filename: "test.ipynb")
        expect(result).to start_with("The cells have been executed.")
        expect(result).to include("Cell 1 (NameError)")
      end
    end

    describe "#clear_jupyter_outputs" do
      it "clears the outputs, and says no kernel was restarted" do
        answer(["", "", true])
        expect(helper.clear_jupyter_outputs(filename: "test.ipynb")).to eq("Cleared the outputs of test.ipynb.")
        expect(asked.last[:command]).to eq("jupyter nbconvert --clear-output --inplace /monadic/data/test.ipynb")
      end

      it "says when the outputs were not cleared" do
        answer(["", "boom", false])
        expect(helper.clear_jupyter_outputs(filename: "test.ipynb")).to start_with("Error: Could not clear the outputs")
        expect(helper.clear_jupyter_outputs(filename: "")).to eq("Error: Filename is required.")
      end
    end
  end

  describe "#list_jupyter_notebooks" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
    end

    context "when notebooks exist" do
      before do
        allow(Dir).to receive(:glob).and_return(["/test/data/notebook1.ipynb", "/test/data/notebook2.ipynb"])
        allow(File).to receive(:basename).and_call_original
        allow(File).to receive(:mtime).and_return(Time.now)
        allow(File).to receive(:size).and_return(1024)
      end

      it "returns list of notebooks" do
        result = helper.list_jupyter_notebooks
        expect(result).to include("notebook1")
        expect(result).to include("notebook2")
      end
    end

    context "when no notebooks exist" do
      before do
        allow(Dir).to receive(:glob).and_return([])
      end

      it "returns message indicating no notebooks" do
        result = helper.list_jupyter_notebooks
        expect(result).to eq("No Jupyter notebooks found in the data directory.")
      end
    end
  end

  describe "Japanese font setup" do
    it "includes Japanese font configuration constant" do
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("Noto Sans CJK JP")
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("matplotlib")
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("font.sans-serif")
    end
  end

  describe "#needs_japanese_font_setup?" do
    it "returns true for cells containing Japanese characters" do
      cells = [{ "source" => "print('こんにちは')" }]
      expect(helper.send(:needs_japanese_font_setup?, cells)).to be true
    end

    it "returns true for cells importing matplotlib" do
      cells = [{ "source" => "import matplotlib.pyplot as plt" }]
      expect(helper.send(:needs_japanese_font_setup?, cells)).to be true
    end

    it "returns false for cells without Japanese or matplotlib" do
      cells = [{ "source" => "print('hello')" }]
      expect(helper.send(:needs_japanese_font_setup?, cells)).to be false
    end
  end
end
