# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require 'open3'
require_relative '../../../lib/monadic/utils/pdf_text_extractor'

RSpec.describe PDF2Text do
  let(:test_pdf_path) { '/tmp/test.pdf' }
  let(:extractor) { described_class.new(path: test_pdf_path) }
  
  # Mock constants
  before do
    stub_const('IN_CONTAINER', false)
    stub_const('MonadicApp::TOKENIZER', double('tokenizer'))
  end
  
  describe '#initialize' do
    it 'sets default values correctly' do
      expect(extractor.file_path).to eq(test_pdf_path)
      expect(extractor.text_data).to eq("")
    end
    
    it 'accepts custom max_tokens' do
      custom_extractor = described_class.new(path: test_pdf_path, max_tokens: 1000)
      expect(custom_extractor.instance_variable_get(:@max_tokens)).to eq(1000)
    end
    
    it 'accepts custom separator' do
      custom_extractor = described_class.new(path: test_pdf_path, separator: ' ')
      expect(custom_extractor.instance_variable_get(:@separator)).to eq(' ')
    end
    
    it 'accepts custom overlap lines' do
      custom_extractor = described_class.new(path: test_pdf_path, overwrap_lines: 2)
      expect(custom_extractor.instance_variable_get(:@overwrap_lines)).to eq(2)
    end
  end
  
  describe '#pdf2text' do
    context 'when file does not exist' do
      it 'raises an error' do
        expect(File).to receive(:exist?).with(test_pdf_path).and_return(false)
        
        expect { extractor.pdf2text(test_pdf_path) }.to raise_error('PDF file not found')
      end
    end
    
    context 'when file exists' do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(FileUtils).to receive(:cp)
        allow(Time).to receive(:now).and_return(Time.at(1234567890))
      end
      
      it 'copies file to data directory with timestamp' do
        mock_stdout = '{"pages": []}'
        allow(Open3).to receive(:capture3).and_return([mock_stdout, '', double(success?: true)])
        
        expect(FileUtils).to receive(:cp).with(
          test_pdf_path,
          File.expand_path('~/monadic/data/1234567890.pdf')
        )
        
        extractor.pdf2text(test_pdf_path)
      end
      
      context 'with successful extraction' do
        it 'returns parsed JSON' do
          mock_json = { "pages" => [{ "text" => "Sample text" }] }
          mock_stdout = mock_json.to_json
          
          allow(Open3).to receive(:capture3).and_return([mock_stdout, '', double(success?: true)])
          
          result = extractor.pdf2text(test_pdf_path)
          expect(result).to eq(mock_json)
        end
      end
      
      context 'with extraction failure' do
        it 'raises error when command fails' do
          allow(Open3).to receive(:capture3).and_return(['', 'Error message', double(success?: false)])
          
          expect { extractor.pdf2text(test_pdf_path) }.to raise_error('Error extracting text: Error message')
        end
        
        it 'raises error for invalid JSON' do
          allow(Open3).to receive(:capture3).and_return(['invalid json', '', double(success?: true)])
          allow(DebugHelper).to receive(:debug)
          
          expect { extractor.pdf2text(test_pdf_path) }.to raise_error('PDF extraction returned invalid JSON format')
        end
      end
      
      context 'when running in container' do
        before do
          stub_const('IN_CONTAINER', true)
        end
        
        it 'uses container data path' do
          mock_stdout = '{"pages": []}'
          allow(Open3).to receive(:capture3).and_return([mock_stdout, '', double(success?: true)])
          
          expect(FileUtils).to receive(:cp).with(
            test_pdf_path,
            '/monadic/data/1234567890.pdf'
          )
          
          extractor.pdf2text(test_pdf_path)
        end
      end
    end
  end
  
  describe '#extract' do
    let(:mock_json) { {} }
    
    before do
      allow(extractor).to receive(:pdf2text).and_return(mock_json)
    end
    
    context 'with valid PDF data' do
      let(:mock_json) do
        {
          "pages" => [
            { "text" => "Page 1 content" },
            { "text" => "Page 2 content" },
            { "text" => "Page 3 with special chars: €£¥" }
          ]
        }
      end
      
      it 'extracts text from all pages' do
        result = extractor.extract
        
        expect(result).to include("Page 1 content")
        expect(result).to include("Page 2 content")
        expect(result).to include("Page 3 with special chars")
      end
      
      it 'removes non-printable characters' do
        mock_json["pages"][0]["text"] = "Text with\x00null\x01chars"
        
        result = extractor.extract
        
        expect(result).not_to include("\x00")
        expect(result).not_to include("\x01")
      end
      
      it 'handles UTF-8 encoding issues' do
        # Create a string with invalid UTF-8 bytes
        invalid_text = "Text with invalid \xFF\xFE bytes".dup.force_encoding('BINARY')
        mock_json["pages"][0]["text"] = invalid_text
        
        expect { extractor.extract }.not_to raise_error
      end
      
      it 'uses parallel processing' do
        expect(Parallel).to receive(:each).with(
          mock_json["pages"],
          in_threads: PDF2Text::THREADS
        ).and_yield(mock_json["pages"][0])
        
        extractor.extract
      end
    end
    
    context 'with empty or corrupted PDF' do
      it 'raises error when pages are nil' do
        local_mock_json = { "pages" => nil }
        allow(extractor).to receive(:pdf2text).and_return(local_mock_json)
        
        expect { extractor.extract }.to raise_error('No pages found in PDF')
      end
      
      it 'raises error when pages are empty' do
        local_mock_json = { "pages" => [] }
        allow(extractor).to receive(:pdf2text).and_return(local_mock_json)
        
        expect { extractor.extract }.to raise_error('No pages found in PDF')
      end
      
      it 'handles corrupted structure gracefully' do
        local_mock_json = { "invalid_key" => "value" }
        allow(extractor).to receive(:pdf2text).and_return(local_mock_json)
        allow(DebugHelper).to receive(:debug)
        
        # When pages key is missing, it raises "No pages found" first
        expect { extractor.extract }.to raise_error('No pages found in PDF')
      end
    end
  end
  
  describe '#split_text' do
    before do
      extractor.instance_variable_set(:@text_data, sample_text)
      allow(MonadicApp::TOKENIZER).to receive(:get_tokens_sequence) do |text|
        # Mock tokenizer - roughly 1 token per word
        text.split.map { |word| word }
      end
    end
    
    context 'with short text' do
      let(:sample_text) { "This is a short text." }
      
      it 'returns single chunk when under max tokens' do
        chunks = extractor.split_text
        
        expect(chunks.length).to eq(1)
        expect(chunks[0]["text"]).to eq(sample_text)
      end
    end
    
    context 'with long text' do
      let(:sample_text) do
        lines = []
        20.times { |i| lines << "Line #{i} with some words to make it longer" }
        lines.join("\n")
      end
      
      before do
        extractor.instance_variable_set(:@max_tokens, 50)
      end
      
      it 'splits text into multiple chunks' do
        chunks = extractor.split_text
        
        expect(chunks.length).to be > 1
        chunks.each do |chunk|
          expect(chunk["tokens"]).to be <= 50
        end
      end
      
      it 'includes overlap lines between chunks' do
        extractor.instance_variable_set(:@overwrap_lines, 2)
        chunks = extractor.split_text
        
        if chunks.length > 1
          # Check that the end of first chunk overlaps with beginning of second
          first_chunk_lines = chunks[0]["text"].split("\n")
          second_chunk_lines = chunks[1]["text"].split("\n")
          
          expect(second_chunk_lines[0..1]).to eq(first_chunk_lines[-2..-1])
        end
      end
    end
    
    context 'with empty text' do
      let(:sample_text) { "" }
      
      it 'returns empty array' do
        chunks = extractor.split_text
        
        expect(chunks).to eq([])
      end
    end
    
    context 'with custom separator' do
      let(:sample_text) { "Part1. Part2. Part3." }
      
      it 'splits using custom separator' do
        extractor.instance_variable_set(:@separator, '. ')
        
        chunks = extractor.split_text
        
        expect(chunks.first["text"]).to include("Part1")
      end
    end
  end
  
  describe 'Edge cases' do
    it 'handles very large PDFs' do
      # Mock a PDF with many pages
      large_pdf = {
        "pages" => Array.new(1000) { |i| { "text" => "Page #{i}" } }
      }
      
      allow(extractor).to receive(:pdf2text).and_return(large_pdf)
      
      expect { extractor.extract }.not_to raise_error
    end
    
    it 'handles PDFs with no text' do
      empty_pdf = {
        "pages" => [
          { "text" => "" },
          { "text" => "" }
        ]
      }
      
      allow(extractor).to receive(:pdf2text).and_return(empty_pdf)
      
      result = extractor.extract
      expect(result.strip).to eq("")
    end
    
    it 'handles mixed encoding in pages' do
      mixed_encoding_pdf = {
        "pages" => [
          { "text" => "UTF-8: こんにちは" },
          { "text" => "Latin-1: café" },
          { "text" => "ASCII: hello" }
        ]
      }
      
      allow(extractor).to receive(:pdf2text).and_return(mixed_encoding_pdf)
      
      expect { extractor.extract }.not_to raise_error
    end
  end
  
  describe 'Integration with tokenizer' do
    it 'correctly counts tokens for splitting' do
      extractor.instance_variable_set(:@text_data, "Test text for tokenization")
      
      # Mock tokenizer to return realistic token sequences
      allow(MonadicApp::TOKENIZER).to receive(:get_tokens_sequence) do |text|
        # Simulate GPT tokenization (roughly 1.3 tokens per word)
        words = text.split
        tokens = []
        words.each do |word|
          tokens << word
          tokens << "" if word.length > 4  # Extra token for longer words
        end
        tokens
      end
      
      chunks = extractor.split_text
      
      expect(chunks).not_to be_empty
      chunks.each do |chunk|
        expect(chunk).to have_key("text")
        expect(chunk).to have_key("tokens")
        expect(chunk["tokens"]).to be_a(Integer)
      end
    end
  end
  
  describe 'Error handling' do
    it 'provides helpful error messages' do
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)
      allow(Open3).to receive(:capture3).and_return(['', 'Docker daemon not running', double(success?: false)])
      
      expect { extractor.pdf2text(test_pdf_path) }.to raise_error(/Error extracting text:.*Docker daemon/)
    end
    
    it 'logs debug information for JSON parse errors' do
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)
      allow(Open3).to receive(:capture3).and_return(['<html>Not JSON</html>', '', double(success?: true)])
      allow(DebugHelper).to receive(:debug)
      
      expect(DebugHelper).to receive(:debug).with(
        /Invalid JSON from pdf2txt.py/,
        "app",
        level: :error
      )
      
      expect { extractor.pdf2text(test_pdf_path) }.to raise_error('PDF extraction returned invalid JSON format')
    end
  end
end