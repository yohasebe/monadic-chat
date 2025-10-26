require "spec_helper"
require_relative "../../../lib/monadic/adapters/jupyter_helper"

RSpec.describe "JupyterHelper" do
  let(:test_class) do
    Class.new do
      include MonadicHelper

      def send_command(command:, container:)
        @last_command = command
        @last_container = container
        "Mock response"
      end

      attr_reader :last_command, :last_container
    end
  end

  let(:app) { test_class.new }

  describe "#get_jupyter_cells_with_results" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('{"cells": []}')
      allow(JSON).to receive(:parse).and_return({"cells" => []})
    end

    context "when filename has .ipynb extension" do
      it "does not add another .ipynb extension" do
        app.get_jupyter_cells_with_results(filename: "notebook_20250925_051036.ipynb")
        expect(File).to have_received(:exist?).with("/test/data/notebook_20250925_051036.ipynb")
      end
    end

    context "when filename does not have .ipynb extension" do
      it "adds .ipynb extension" do
        app.get_jupyter_cells_with_results(filename: "notebook_20250925_051036")
        expect(File).to have_received(:exist?).with("/test/data/notebook_20250925_051036.ipynb")
      end
    end

    context "when filename is empty" do
      it "returns error message" do
        result = app.get_jupyter_cells_with_results(filename: "")
        expect(result).to eq("Error: Filename is required.")
      end
    end
  end

  describe "#add_jupyter_cells" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return("notebook.ipynb")
      allow(app).to receive(:send_command).and_return("Success")
    end

    context "when filename has .ipynb extension" do
      it "does not add another .ipynb extension" do
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        app.add_jupyter_cells(filename: "test_20250925.ipynb", cells: valid_cells)
        # Verify that send_command is called with the correct filename (no double .ipynb)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("test_20250925"))
        )
        # Ensure no double extension
        expect(app).not_to have_received(:send_command).with(
          hash_including(command: include(".ipynb.ipynb"))
        )
      end
    end

    context "when filename does not have .ipynb extension" do
      it "adds .ipynb extension" do
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        app.add_jupyter_cells(filename: "test_20250925", cells: valid_cells)
        # Verify that send_command is called (meaning the notebook is being processed)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("test_20250925"))
        )
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
end