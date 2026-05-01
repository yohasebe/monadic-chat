# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::Office do
  let(:schema) { Monadic::Library::Schema }

  let(:docx_markdown) do
    <<~MD
      # Project Plan

      This document outlines the rollout plan for the new feature. The
      first paragraph contains enough text to ensure the resulting turn
      passes the minimum length filter.

      ## Goals

      We aim to launch in three phases. Each phase has measurable
      success criteria so we can decide whether to proceed.

      ## Risks

      Several risks have been identified, including upstream API
      changes, capacity constraints, and seasonal traffic spikes.
    MD
  end

  let(:xlsx_markdown) do
    <<~MD
      # Sheet1

      header1 | header2 | header3
      a | b | c
      d | e | f

      # Sheet2

      x | y
      1 | 2
      3 | 4
    MD
  end

  let(:pptx_markdown) do
    <<~MD
      # Welcome

      Slide one body content describes the product introduction in
      enough words that the chunk passes the minimum-length filter.

      # Architecture

      Here we describe the system architecture as a series of bullet
      points. Each bullet is on its own line per the extractor.

      # Roadmap

      The roadmap covers three quarters and is segmented by team.
    MD
  end

  describe '.import (docx)' do
    let(:result) { described_class.import(docx_markdown, filename: 'plan.docx', format: 'docx') }

    it 'produces a schema-valid v1 conversation' do
      expect(schema.valid?(result)).to be true
    end

    it 'splits sections on H1/H2 headings' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('# Project Plan') }).to be true
      expect(texts.any? { |t| t.start_with?('## Goals') }).to be true
      expect(texts.any? { |t| t.start_with?('## Risks') }).to be true
    end

    it 'sets content_type=document' do
      expect(result.dig('conversation_metadata', 'content_type')).to eq('document')
    end

    it 'records sub-format docx in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('docx')
    end

    it 'sets participant description=office_document' do
      expect(result['participants'].first['description']).to eq('office_document')
    end

    it 'derives source from filename with office: prefix' do
      expect(result.dig('conversation_metadata', 'source')).to eq('office:plan.docx')
    end

    it 'auto-derives title from filename when no title given' do
      expect(result.dig('conversation_metadata', 'title')).to eq('plan')
    end
  end

  describe '.import (xlsx)' do
    let(:result) { described_class.import(xlsx_markdown, filename: 'data.xlsx', format: 'xlsx') }

    it 'produces a schema-valid v1 conversation' do
      expect(schema.valid?(result)).to be true
    end

    it 'splits each sheet into its own message' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.any? { |t| t.start_with?('# Sheet1') }).to be true
      expect(texts.any? { |t| t.start_with?('# Sheet2') }).to be true
    end

    it 'records sub-format xlsx in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('xlsx')
    end

    it 'sets participant description=office_spreadsheet' do
      expect(result['participants'].first['description']).to eq('office_spreadsheet')
    end
  end

  describe '.import (pptx)' do
    let(:result) { described_class.import(pptx_markdown, filename: 'deck.pptx', format: 'pptx') }

    it 'produces a schema-valid v1 conversation' do
      expect(schema.valid?(result)).to be true
    end

    it 'splits each slide into its own message' do
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.size).to eq(3)
      expect(texts[0]).to start_with('# Welcome')
      expect(texts[1]).to start_with('# Architecture')
      expect(texts[2]).to start_with('# Roadmap')
    end

    it 'records sub-format pptx in topics' do
      expect(result.dig('conversation_metadata', 'topics')).to include('pptx')
    end

    it 'sets participant description=office_presentation' do
      expect(result['participants'].first['description']).to eq('office_presentation')
    end
  end

  describe '.import_extraction_json' do
    it 'parses extractor output and applies title from doc properties' do
      json = { 'title' => 'Q3 Report', 'author' => 'Jane Doe',
               'format' => 'docx', 'markdown' => docx_markdown }.to_json
      result = described_class.import_extraction_json(json, filename: 'q3.docx')
      expect(schema.valid?(result)).to be true
      expect(result.dig('conversation_metadata', 'title')).to eq('Q3 Report')
      expect(result['participants'].first['label']).to eq('Q3 Report')
      expect(result.dig('conversation_metadata', 'topics')).to include('docx')
    end

    it 'caller-supplied title beats document properties title' do
      json = { 'title' => 'Q3 Report', 'format' => 'docx', 'markdown' => docx_markdown }.to_json
      result = described_class.import_extraction_json(json, filename: 'q3.docx', title: 'Override')
      expect(result.dig('conversation_metadata', 'title')).to eq('Override')
    end

    it 'tolerates missing optional fields' do
      bare = { 'format' => 'xlsx', 'markdown' => xlsx_markdown }.to_json
      result = described_class.import_extraction_json(bare, filename: 'bare.xlsx')
      expect(schema.valid?(result)).to be true
    end
  end

  describe 'unknown format defaults to docx profile' do
    it 'falls back gracefully when format is missing' do
      result = described_class.import(docx_markdown, filename: 'mystery.bin')
      expect(schema.valid?(result)).to be true
      expect(result['participants'].first['description']).to eq('office_document')
    end
  end

  describe 'integration with TurnSegmenter (monologue → per-message turns)' do
    it 'produces one turn per Office section (docx)' do
      conv = described_class.import(docx_markdown, filename: 'plan.docx', format: 'docx')
      turns = Monadic::Library::TurnSegmenter.segment(conv)
      expect(turns.size).to eq(conv['messages'].size)
    end

    it 'produces one turn per slide (pptx)' do
      conv = described_class.import(pptx_markdown, filename: 'deck.pptx', format: 'pptx')
      turns = Monadic::Library::TurnSegmenter.segment(conv)
      expect(turns.size).to eq(3)
    end
  end

  describe 'edge cases' do
    it 'raises when content is empty' do
      expect { described_class.import("\n\n  \n", format: 'docx') }
        .to raise_error(ArgumentError, /no sections/)
    end
  end
end
