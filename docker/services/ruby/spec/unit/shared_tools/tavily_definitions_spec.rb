# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/shared_tools/tavily_definitions'

RSpec.describe Monadic::SharedTools::TavilyDefinitions do
  describe 'TOOLS' do
    let(:tools) { described_class::TOOLS }

    it 'exposes exactly two function tools' do
      expect(tools.size).to eq(2)
      expect(tools.map { |t| t.dig(:function, :name) }).to contain_exactly('tavily_fetch', 'tavily_search')
    end

    it 'requires only `url` for tavily_fetch' do
      fetch_tool = tools.find { |t| t.dig(:function, :name) == 'tavily_fetch' }
      expect(fetch_tool.dig(:function, :parameters, :required)).to eq(['url'])
    end

    it 'requires only `query` for tavily_search (n must remain optional)' do
      # Before consolidation, Cohere forced `n` to be required which
      # made models pass arbitrary counts. The canonical contract
      # leaves n optional so the Tavily default (3) takes effect.
      search_tool = tools.find { |t| t.dig(:function, :name) == 'tavily_search' }
      expect(search_tool.dig(:function, :parameters, :required)).to eq(['query'])
    end

    it 'is frozen so consumers cannot mutate the shared array' do
      expect(tools).to be_frozen
    end
  end

  describe 'PROMPT' do
    let(:prompt) { described_class::PROMPT }

    it 'is a non-empty string' do
      expect(prompt).to be_a(String)
      expect(prompt.length).to be > 0
    end

    it 'is concise enough not to overwhelm the surrounding system prompt' do
      # See Prompt design notes in tavily_definitions.rb — kept under
      # ~25 lines so smaller models do not drift into English.
      expect(prompt.lines.size).to be < 25
    end

    it 'mentions both tools by name so the LLM knows what is available' do
      expect(prompt).to include('tavily_search')
      expect(prompt).to include('tavily_fetch')
    end

    it 'instructs the model to respond in the user\'s language' do
      # Without this nudge, smaller models slip into English responses
      # whenever the surrounding English prompt is long.
      expect(prompt).to match(/respond.*in the language/i)
    end

    it 'specifies the citation format with secure rel attributes' do
      expect(prompt).to include('target="_blank"')
      expect(prompt).to include('rel="noopener noreferrer"')
    end
  end

  describe 'helper modules adopt the shared constants' do
    # The four Tavily-fallback helpers must alias their local
    # WEBSEARCH_TOOLS / WEBSEARCH_PROMPT to the shared module so
    # there's exactly one source of truth.
    let(:vendors_dir) do
      File.join(File.dirname(__FILE__), '../../../lib/monadic/adapters/vendors')
    end

    {
      'cohere_helper.rb' => 'CohereHelper',
      'deepseek_helper.rb' => 'DeepSeekHelper',
      'mistral_helper.rb' => 'MistralHelper',
      'ollama_helper.rb' => 'OllamaHelper'
    }.each do |filename, _label|
      it "#{filename} aliases WEBSEARCH_TOOLS to Monadic::SharedTools::TavilyDefinitions::TOOLS" do
        content = File.read(File.join(vendors_dir, filename))
        expect(content).to match(
          /WEBSEARCH_TOOLS\s*=\s*Monadic::SharedTools::TavilyDefinitions::TOOLS/
        )
      end

      it "#{filename} aliases WEBSEARCH_PROMPT to Monadic::SharedTools::TavilyDefinitions::PROMPT" do
        content = File.read(File.join(vendors_dir, filename))
        expect(content).to match(
          /WEBSEARCH_PROMPT\s*=\s*Monadic::SharedTools::TavilyDefinitions::PROMPT/
        )
      end

      it "#{filename} does NOT redefine WEBSEARCH_TOOLS as a literal array" do
        # Catches accidental "I'll just copy it back in for now" drift.
        content = File.read(File.join(vendors_dir, filename))
        expect(content).not_to match(/WEBSEARCH_TOOLS\s*=\s*\[/)
      end

      it "#{filename} does NOT redefine WEBSEARCH_PROMPT as a literal heredoc" do
        content = File.read(File.join(vendors_dir, filename))
        expect(content).not_to match(/WEBSEARCH_PROMPT\s*=\s*<<~?[A-Z]/)
      end
    end
  end
end
