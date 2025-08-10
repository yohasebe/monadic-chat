require 'spec_helper'
require 'json'
require 'tempfile'

RSpec.describe MonadicHelper do
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      # Mock methods needed by jupyter_helper
      def send_command(command:, container:, success: nil, success_with_output: nil)
        success || "Command executed"
      end
      
      def write_to_file(filename:, extension:, text:)
        true
      end
      
      def self.capture_command(command, timeout: nil)
        ["", "", OpenStruct.new(success?: true)]
      end
    end
  end
  
  let(:helper) { test_class.new }
  
  describe '#normalize_cell_format' do
    context 'with correctly formatted cells' do
      it 'preserves correct format' do
        cells = [
          { "cell_type" => "code", "source" => "print('hello')" },
          { "cell_type" => "markdown", "source" => "# Title" }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result).to eq(cells)
      end
    end
    
    context 'with incorrectly ordered fields' do
      it 'reorders fields correctly' do
        cells = [
          { "source" => "print('hello')", "cell_type" => "code" },
          { "source" => "# Title", "cell_type" => "markdown" }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result[0]["cell_type"]).to eq("code")
        expect(result[0]["source"]).to eq("print('hello')")
        expect(result[1]["cell_type"]).to eq("markdown")
      end
    end
    
    context 'with symbol keys' do
      it 'converts symbol keys to strings' do
        cells = [
          { cell_type: "code", source: "import numpy" },
          { :cell_type => "markdown", :source => "## Header" }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result[0]).to have_key("cell_type")
        expect(result[0]).to have_key("source")
        expect(result[0]["cell_type"]).to eq("code")
      end
    end
    
    context 'with array sources' do
      it 'joins array sources into single string' do
        cells = [
          { "cell_type" => "code", "source" => ["line 1", "line 2", "line 3"] }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result[0]["source"]).to eq("line 1\nline 2\nline 3")
      end
    end
    
    context 'with alternative field names' do
      it 'maps content to source' do
        cells = [
          { "cell_type" => "code", "content" => "print('test')" },
          { "type" => "markdown", "source" => "# Title" }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result[0]["source"]).to eq("print('test')")
        expect(result[1]["cell_type"]).to eq("markdown")
      end
    end
    
    context 'with missing cell_type' do
      it 'defaults to code' do
        cells = [
          { "source" => "print('no type')" }
        ]
        
        result = helper.normalize_cell_format(cells)
        expect(result[0]["cell_type"]).to eq("code")
      end
    end
    
    context 'with non-array input' do
      it 'returns input unchanged' do
        expect(helper.normalize_cell_format("not an array")).to eq("not an array")
        expect(helper.normalize_cell_format(nil)).to eq(nil)
      end
    end
  end
  
  describe '#verify_cells_added' do
    let(:test_filename) { "test_notebook" }
    let(:test_cells) { [{"cell_type" => "code", "source" => "print('test')"}] }
    
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/tmp")
    end
    
    context 'when notebook exists with cells' do
      it 'returns success' do
        notebook_content = {
          "cells" => [
            {"cell_type" => "code", "source" => "print('test')"}
          ]
        }
        
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return(notebook_content.to_json)
        
        result = helper.verify_cells_added(test_filename, test_cells)
        expect(result[:success]).to be true
      end
    end
    
    context 'when notebook does not exist' do
      it 'returns error' do
        allow(File).to receive(:exist?).and_return(false)
        
        result = helper.verify_cells_added(test_filename, test_cells)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end
    
    context 'when notebook has no cells' do
      it 'returns error' do
        notebook_content = { "cells" => [] }
        
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return(notebook_content.to_json)
        
        result = helper.verify_cells_added(test_filename, test_cells)
        expect(result[:success]).to be false
        expect(result[:error]).to include("No cells found")
      end
    end
    
    context 'when JSON parsing fails' do
      it 'returns error with message' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("invalid json")
        
        result = helper.verify_cells_added(test_filename, test_cells)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Verification error")
      end
    end
  end
  
  describe '#log_jupyter_error' do
    let(:log_file) { MonadicHelper::JUPYTER_LOG_FILE }
    
    before do
      allow(File).to receive(:open).and_yield(StringIO.new)
    end
    
    it 'logs error information' do
      io = StringIO.new
      allow(File).to receive(:open).with(log_file, "a").and_yield(io)
      
      helper.log_jupyter_error("Test operation", "test.ipynb", 
                              [{"cell_type" => "code"}], "Test error")
      
      expect(io.string).to include("ERROR Time:")
      expect(io.string).to include("Operation: Test operation")
      expect(io.string).to include("Filename: test.ipynb")
      expect(io.string).to include("Error: Test error")
    end
    
    it 'silently fails if logging fails' do
      allow(File).to receive(:open).and_raise(StandardError)
      
      expect {
        helper.log_jupyter_error("Test", "test", [], "error")
      }.not_to raise_error
    end
  end
end