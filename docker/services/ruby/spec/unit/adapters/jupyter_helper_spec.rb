# frozen_string_literal: true

require "spec_helper"
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
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return(notebook_content)
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
        expect(File).to have_received(:exist?).with("/test/data/test.ipynb")
      end
    end

    context "when notebook does not exist" do
      before do
        allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
        allow(File).to receive(:exist?).and_return(false)
      end

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

  describe "#restart_jupyter_kernel" do
    it "returns error when filename is empty" do
      result = helper.restart_jupyter_kernel(filename: "")
      expect(result).to eq("Error: Filename is required.")
    end

    it "sends restart command to Python container" do
      allow(helper).to receive(:send_command).and_return("Kernel restarted")
      result = helper.restart_jupyter_kernel(filename: "test.ipynb")
      expect(result).to include("Successfully restarted kernel")
    end
  end

  describe "#interrupt_jupyter_execution" do
    it "returns error when filename is empty" do
      result = helper.interrupt_jupyter_execution(filename: "")
      expect(result).to eq("Error: Filename is required.")
    end

    it "returns limitation message for valid filename" do
      result = helper.interrupt_jupyter_execution(filename: "test.ipynb")
      expect(result).to include("Direct kernel interrupt is not currently supported")
    end
  end

  describe "#move_jupyter_cell" do
    it "returns error when filename is empty" do
      result = helper.move_jupyter_cell(filename: "", from_index: 0, to_index: 1)
      expect(result).to eq("Error: Filename is required.")
    end

    it "returns error for negative from_index" do
      result = helper.move_jupyter_cell(filename: "test.ipynb", from_index: -1, to_index: 1)
      expect(result).to eq("Error: Invalid indices.")
    end

    it "returns error for negative to_index" do
      result = helper.move_jupyter_cell(filename: "test.ipynb", from_index: 0, to_index: -1)
      expect(result).to eq("Error: Invalid indices.")
    end

    it "returns success message for valid parameters" do
      result = helper.move_jupyter_cell(filename: "test.ipynb", from_index: 0, to_index: 1)
      expect(result).to include("Successfully moved cell")
    end
  end

  describe "#insert_jupyter_cells" do
    it "returns error when filename is empty" do
      result = helper.insert_jupyter_cells(filename: "", index: 0, cells: [{ "cell_type" => "code" }])
      expect(result).to eq("Error: Filename is required.")
    end

    it "returns error when cells is empty" do
      result = helper.insert_jupyter_cells(filename: "test.ipynb", index: 0, cells: [])
      expect(result).to eq("Error: Cells are required.")
    end

    it "returns error for negative index" do
      result = helper.insert_jupyter_cells(filename: "test.ipynb", index: -1, cells: [{ "cell_type" => "code" }])
      expect(result).to eq("Error: Invalid index.")
    end

    it "returns success message for valid parameters" do
      cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
      result = helper.insert_jupyter_cells(filename: "test.ipynb", index: 0, cells: cells)
      expect(result).to include("Successfully inserted")
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
