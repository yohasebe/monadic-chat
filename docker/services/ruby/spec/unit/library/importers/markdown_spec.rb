# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::Markdown do
  let(:schema) { Monadic::Library::Schema }

  let(:simple_input) do
    <<~MD
      # Introduction

      The opening paragraph sets the scene with enough detail to anchor the
      reader before the first sub-heading. We deliberately make this a few
      sentences long so the section turns are large enough to embed.

      ## Background

      This section explains the historical context. It contains a couple of
      sentences and references prior work without going into deep detail.

      ## Method

      We list the steps:

      1. Step one
      2. Step two
      3. Step three
    MD
  end

  let(:frontmatter_input) do
    <<~MD
      ---
      title: Field Notes
      language: en
      topics:
        - botany
        - field-research
      license: CC-BY-4.0
      ---

      # Day 1

      The first day in the field began before dawn. We covered the route
      from the trailhead to the basin and recorded the dominant species.
    MD
  end

  describe '.can_import?' do
    it 'recognises content with a heading' do
      expect(described_class.can_import?("# Title\n\nbody.")).to be true
    end

    it 'recognises a frontmatter fence even without headings' do
      expect(described_class.can_import?("---\nfoo: 1\n---\nbody")).to be true
    end

    it 'recognises a fenced code block' do
      expect(described_class.can_import?("intro\n```ruby\np 1\n```\n")).to be true
    end

    it 'rejects empty input' do
      expect(described_class.can_import?('')).to be false
      expect(described_class.can_import?(nil)).to be false
    end
  end

  describe '.import' do
    it 'produces a schema-valid v1 conversation' do
      result = described_class.import(simple_input)
      expect(schema.valid?(result)).to be true
    end

    it 'splits sections on H1/H2 headings' do
      result = described_class.import(simple_input)
      texts = result['messages'].map { |m| m['text'] }
      expect(texts.size).to eq(3)
      expect(texts[0]).to start_with('# Introduction')
      expect(texts[1]).to start_with('## Background')
      expect(texts[2]).to start_with('## Method')
    end

    it 'creates a single narrator participant' do
      result = described_class.import(simple_input, filename: 'notes.md')
      expect(result['participants'].size).to eq(1)
      p = result['participants'].first
      expect(p['role']).to eq('narrator')
      expect(p['description']).to eq('markdown_document')
      expect(p['label']).to eq('notes.md')
    end

    it 'sets content_type=markdown in conversation_metadata' do
      result = described_class.import(simple_input)
      expect(result.dig('conversation_metadata', 'content_type')).to eq('markdown')
    end

    it 'derives source from filename when provided' do
      result = described_class.import(simple_input, filename: '/tmp/notes.md')
      expect(result.dig('conversation_metadata', 'source')).to eq('markdown:notes.md')
    end

    it 'falls back to "markdown" source without filename' do
      result = described_class.import(simple_input)
      expect(result.dig('conversation_metadata', 'source')).to eq('markdown')
    end

    it 'promotes YAML frontmatter into conversation_metadata' do
      result = described_class.import(frontmatter_input)
      meta = result['conversation_metadata']
      expect(schema.valid?(result)).to be true
      expect(meta['title']).to eq('Field Notes')
      expect(meta['language']).to eq('en')
      expect(meta['topics']).to eq(%w[botany field-research])
      expect(meta['license']).to eq('CC-BY-4.0')
    end

    it 'caller-supplied options win over frontmatter' do
      result = described_class.import(frontmatter_input, title: 'Override')
      expect(result.dig('conversation_metadata', 'title')).to eq('Override')
    end

    it 'falls back to paragraph blocks when no headings are present' do
      body = (['Paragraph one. ' * 30, 'Paragraph two. ' * 30, 'Paragraph three. ' * 30]).join("\n\n")
      result = described_class.import(body)
      expect(schema.valid?(result)).to be true
      expect(result['messages'].size).to be >= 1
    end

    it 'shares the same speaker across all messages (monologue shape)' do
      result = described_class.import(simple_input)
      ids = result['messages'].map { |m| m.dig('speaker', 'id') }.uniq
      expect(ids).to eq(['document'])
    end

    it 'raises when input has no extractable content' do
      expect {
        described_class.import("\n\n\n")
      }.to raise_error(ArgumentError, /no sections/)
    end
  end

  describe 'integration with TurnSegmenter (monologue → per-message turns)' do
    it 'produces one turn per Markdown section' do
      conv = described_class.import(simple_input)
      turns = Monadic::Library::TurnSegmenter.segment(conv)
      expect(turns.size).to eq(3)
      expect(turns.first[:text]).to start_with('# Introduction')
    end
  end
end
