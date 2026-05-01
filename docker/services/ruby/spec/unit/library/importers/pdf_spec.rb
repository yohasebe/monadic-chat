# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::Pdf do
  let(:schema) { Monadic::Library::Schema }

  # Simulated pymupdf4llm.to_markdown() output.
  let(:markdown_content) do
    <<~MD
      # Abstract

      This paper introduces a method for testing PDF importers without
      involving an actual PDF file. We rely on canned markdown that
      mirrors what pymupdf4llm.to_markdown() emits in production.

      # Introduction

      The introduction provides historical background. It is long enough
      that the resulting turn passes the minimum length filter.

      ## Prior Work

      Various prior systems have approached this problem. We highlight
      three influential lines of research and explain why our approach
      differs from each.

      # Method

      We use a three-step pipeline:

      1. Extract text via pymupdf4llm
      2. Split on heading boundaries
      3. Embed each section
    MD
  end

  let(:extraction_json) do
    {
      'title' => 'A Test Paper',
      'author' => 'Jane Doe',
      'page_count' => 12,
      'markdown' => markdown_content
    }.to_json
  end

  describe '.import' do
    let(:result) { described_class.import(markdown_content, filename: 'paper.pdf') }

    it 'produces a schema-valid v1 conversation' do
      expect(schema.valid?(result)).to be true
    end

    it 'splits sections on H1/H2 headings' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('# Abstract') }).to be true
      expect(texts.any? { |t| t.start_with?('# Introduction') }).to be true
      expect(texts.any? { |t| t.start_with?('## Prior Work') }).to be true
      expect(texts.any? { |t| t.start_with?('# Method') }).to be true
    end

    it 'creates a single narrator participant with description=pdf_document' do
      expect(result['participants'].size).to eq(1)
      p = result['participants'].first
      expect(p['role']).to eq('narrator')
      expect(p['description']).to eq('pdf_document')
    end

    it 'sets content_type=pdf' do
      expect(result.dig('conversation_metadata', 'content_type')).to eq('pdf')
    end

    it 'derives source from filename' do
      expect(result.dig('conversation_metadata', 'source')).to eq('pdf:paper.pdf')
    end

    it 'falls back to "pdf" source without filename' do
      result = described_class.import(markdown_content)
      expect(result.dig('conversation_metadata', 'source')).to eq('pdf')
    end

    it 'uses title option for participant label when provided' do
      result = described_class.import(markdown_content, filename: 'p.pdf', title: 'My PDF')
      expect(result['participants'].first['label']).to eq('My PDF')
      expect(result.dig('conversation_metadata', 'title')).to eq('My PDF')
    end

    it 'falls back to author for participant label when no title' do
      result = described_class.import(markdown_content, filename: 'p.pdf', author: 'Alice')
      expect(result['participants'].first['label']).to eq('Alice')
    end

    it 'shares the same speaker across all messages' do
      ids = result['messages'].map { |m| m.dig('speaker', 'id') }.uniq
      expect(ids).to eq(['document'])
    end

    it 'falls back to paragraph blocks when no headings are present' do
      body = (['Sentence text. ' * 30, 'Another paragraph. ' * 30, 'Third paragraph. ' * 30]).join("\n\n")
      result = described_class.import(body, filename: 'flat.pdf')
      expect(schema.valid?(result)).to be true
      expect(result['messages']).not_to be_empty
    end

    it 'raises when content is empty' do
      expect { described_class.import("\n\n  \n") }
        .to raise_error(ArgumentError, /no sections/)
    end
  end

  describe '.import_extraction_json' do
    it 'parses the extractor JSON and applies title/author from PDF metadata' do
      result = described_class.import_extraction_json(extraction_json, filename: 'paper.pdf')
      expect(schema.valid?(result)).to be true
      expect(result.dig('conversation_metadata', 'title')).to eq('A Test Paper')
      expect(result['participants'].first['label']).to eq('A Test Paper')
    end

    it 'caller-supplied title beats PDF metadata title' do
      result = described_class.import_extraction_json(extraction_json, filename: 'paper.pdf', title: 'Override')
      expect(result.dig('conversation_metadata', 'title')).to eq('Override')
    end

    it 'preserves source format pdf:filename' do
      result = described_class.import_extraction_json(extraction_json, filename: 'paper.pdf')
      expect(result.dig('conversation_metadata', 'source')).to eq('pdf:paper.pdf')
    end

    it 'tolerates missing PDF metadata fields' do
      bare = { 'markdown' => markdown_content }.to_json
      result = described_class.import_extraction_json(bare, filename: 'bare.pdf')
      expect(schema.valid?(result)).to be true
    end
  end

  describe 'integration with TurnSegmenter (monologue → per-message turns)' do
    it 'produces one turn per PDF section' do
      conv = described_class.import(markdown_content, filename: 'paper.pdf')
      turns = Monadic::Library::TurnSegmenter.segment(conv)
      expect(turns.size).to eq(conv['messages'].size)
    end
  end
end
