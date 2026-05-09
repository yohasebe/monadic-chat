# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::Code do
  let(:schema) { Monadic::Library::Schema }

  let(:ruby_input) do
    <<~RUBY
      # frozen_string_literal: true

      require 'json'

      module Greeting
        def self.hello(name)
          "Hello, \#{name}"
        end
      end

      class Greeter
        def initialize(language)
          @language = language
        end

        def greet(name)
          Greeting.hello(name)
        end
      end

      def standalone_helper(value)
        value.to_s.strip
      end
    RUBY
  end

  let(:python_input) do
    <<~PY
      """Module docstring."""
      import os

      CONSTANT = 42

      def add(a, b):
          return a + b


      class Calculator:
          def __init__(self):
              self.history = []

          def add(self, a, b):
              return a + b


      async def fetch_data(url):
          return await get(url)
    PY
  end

  let(:js_input) do
    <<~JS
      import fs from 'fs';

      const PORT = 3000;

      function startServer() {
        return fs.createReadStream();
      }

      class Router {
        constructor() {
          this.routes = [];
        }
      }

      export default Router;
    JS
  end

  let(:go_input) do
    <<~GO
      package main

      import "fmt"

      type Greeter struct {
          Name string
      }

      func main() {
          fmt.Println("hello")
      }

      func helper() string {
          return "ok"
      }
    GO
  end

  describe '.can_import?' do
    it 'recognises Ruby source' do
      expect(described_class.can_import?(ruby_input)).to be true
    end

    it 'recognises Python source' do
      expect(described_class.can_import?(python_input)).to be true
    end

    it 'rejects empty input' do
      expect(described_class.can_import?('')).to be false
      expect(described_class.can_import?(nil)).to be false
    end

    it 'rejects plain prose' do
      expect(described_class.can_import?("Just some prose without any code patterns.\n")).to be false
    end
  end

  describe '.import (Ruby)' do
    let(:result) { described_class.import(ruby_input, filename: 'greeter.rb') }

    it 'produces a schema-valid v1 conversation' do
      expect(schema.valid?(result)).to be true
    end

    it 'preserves shebang/require preamble as the first section' do
      first = result['messages'].first['text']
      expect(first).to include('frozen_string_literal')
      expect(first).to include("require 'json'")
    end

    it 'splits on def/class/module boundaries' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('module Greeting') }).to be true
      expect(texts.any? { |t| t.start_with?('class Greeter') }).to be true
      expect(texts.any? { |t| t.start_with?('def standalone_helper') }).to be true
    end

    it 'records programming language in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('ruby')
    end

    it 'leaves human language as default ISO 639-1 ("en")' do
      expect(result.dig('conversation_metadata', 'language')).to eq('en')
    end

    it 'sets content_type=code' do
      expect(result.dig('conversation_metadata', 'content_type')).to eq('code')
    end

    it 'derives source from filename' do
      expect(result.dig('conversation_metadata', 'source')).to eq('code:greeter.rb')
    end

    it 'auto-derives title from filename when no title is given' do
      expect(result.dig('conversation_metadata', 'title')).to eq('greeter')
    end

    it 'caller-supplied title wins over filename derivation' do
      result = described_class.import(ruby_input, filename: 'greeter.rb', title: 'My Greeter')
      expect(result.dig('conversation_metadata', 'title')).to eq('My Greeter')
    end
  end

  describe '.import (Python)' do
    let(:result) { described_class.import(python_input, filename: 'calc.py') }

    it 'splits on def/class/async def at column 0' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('def add') }).to be true
      expect(texts.any? { |t| t.start_with?('class Calculator') }).to be true
      expect(texts.any? { |t| t.start_with?('async def fetch_data') }).to be true
    end

    it 'does NOT split on indented (method-level) defs inside a class' do
      texts = result['messages'].map { |m| m['text'] }
      calc_section = texts.find { |t| t.start_with?('class Calculator') }
      expect(calc_section).to include('def __init__')
      expect(calc_section).to include('def add')
    end

    it 'records python in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('python')
    end
  end

  describe '.import (JavaScript)' do
    let(:result) { described_class.import(js_input, filename: 'server.js') }

    it 'splits on function/class/const-arrow boundaries' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('function startServer') }).to be true
      expect(texts.any? { |t| t.start_with?('class Router') }).to be true
    end

    it 'records javascript in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('javascript')
    end
  end

  describe '.import (Go)' do
    let(:result) { described_class.import(go_input, filename: 'main.go') }

    it 'splits on func/type boundaries' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('type Greeter') }).to be true
      expect(texts.any? { |t| t.start_with?('func main') }).to be true
      expect(texts.any? { |t| t.start_with?('func helper') }).to be true
    end
  end

  describe 'language detection' do
    it 'maps .ts → typescript' do
      result = described_class.import("export const foo = 1;\n", filename: 'a.ts')
      expect(result.dig('conversation_metadata', 'topics')).to include('typescript')
    end

    it 'maps Rakefile basename → ruby' do
      result = described_class.import("task :default => :spec\n", filename: 'Rakefile')
      expect(result.dig('conversation_metadata', 'topics')).to include('ruby')
    end

    it 'maps Gemfile basename → ruby' do
      result = described_class.import("source 'https://rubygems.org'\n\ngem 'rails'\n", filename: 'Gemfile')
      expect(result.dig('conversation_metadata', 'topics')).to include('ruby')
    end

    it 'allows :programming_language option to override extension inference' do
      result = described_class.import(ruby_input, filename: 'mystery.txt', programming_language: 'ruby')
      expect(result.dig('conversation_metadata', 'topics')).to include('ruby')
    end

    it 'falls back to paragraph splitting for unknown languages' do
      content = ([('A' * 250), ('B' * 250), ('C' * 250)]).join("\n\n")
      result = described_class.import(content, filename: 'unknown.xyz')
      expect(schema.valid?(result)).to be true
      expect(result['messages']).not_to be_empty
    end
  end

  describe 'source field' do
    it 'falls back to "code" when no filename is provided' do
      result = described_class.import(ruby_input)
      expect(result.dig('conversation_metadata', 'source')).to eq('code')
    end

    it 'uses basename of an absolute path' do
      result = described_class.import(ruby_input, filename: '/Users/me/proj/lib/foo.rb')
      expect(result.dig('conversation_metadata', 'source')).to eq('code:foo.rb')
    end
  end

  describe 'integration with TurnSegmenter (monologue → per-message turns)' do
    it 'produces one turn per code section' do
      conv = described_class.import(ruby_input, filename: 'greeter.rb')
      turns = Monadic::Library::TurnSegmenter.segment(conv)
      expect(turns.size).to eq(conv['messages'].size)
    end
  end

  describe 'edge cases' do
    it 'raises when input is whitespace only' do
      expect { described_class.import("\n\n   \n") }
        .to raise_error(ArgumentError, /no sections/)
    end

    it 'handles a single short snippet without boundaries (paragraph fallback)' do
      result = described_class.import("puts 'hi'\n", filename: 'tiny.rb')
      expect(schema.valid?(result)).to be true
      expect(result['messages'].size).to eq(1)
    end
  end
end
