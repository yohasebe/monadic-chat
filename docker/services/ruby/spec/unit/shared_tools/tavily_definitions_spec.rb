# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/shared_tools/tavily_definitions'
require_relative '../../../lib/monadic/shared_tools/registry'

RSpec.describe Monadic::SharedTools::TavilyDefinitions do
  # WEB_SEARCH_TOOL_NAMES drives the consumption-point gate (web_search_tool?)
  # that blocks web search when the toggle is off. The exposure-point gate
  # (ProgressiveToolManager) derives the group from the Registry, so if a tool
  # is added to the web_search_tools group but not here, the two gates drift and
  # the new tool escapes the toggle. Lock them together.
  it 'WEB_SEARCH_TOOL_NAMES matches the web_search_tools Registry group (no drift)' do
    registry_names = MonadicSharedTools::Registry.tools_for(:web_search_tools).map { |t| t[:name] }
    expect(described_class::WEB_SEARCH_TOOL_NAMES.sort).to eq(registry_names.sort)
  end

  describe '.web_search_tool?' do
    it 'recognizes every web-search tool name (schema + Tavily primitives)' do
      %w[search_web fetch_web_content tavily_search tavily_fetch].each do |name|
        expect(described_class.web_search_tool?(name)).to be(true), "expected #{name} to be a web-search tool"
      end
    end

    it 'accepts symbols as well as strings' do
      expect(described_class.web_search_tool?(:tavily_search)).to be(true)
    end

    it 'returns false for unrelated tools' do
      %w[read_file_from_shared_folder run_code request_tool library_search].each do |name|
        expect(described_class.web_search_tool?(name)).to be(false)
      end
    end
  end

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

  describe '.websearch_requested?' do
    around do |example|
      original = defined?(CONFIG) ? CONFIG.dup : nil
      example.run
    ensure
      if original
        CONFIG.clear
        CONFIG.merge!(original)
      end
    end

    before { stub_const('CONFIG', { 'TAVILY_API_KEY' => 'key-123' }) }

    it 'is true for boolean true and string "true"' do
      expect(described_class.websearch_requested?('websearch' => true)).to be true
      expect(described_class.websearch_requested?('websearch' => 'true')).to be true
    end

    it 'is false when the flag is absent, false, or any other value' do
      expect(described_class.websearch_requested?({})).to be false
      expect(described_class.websearch_requested?('websearch' => false)).to be false
      expect(described_class.websearch_requested?('websearch' => 'false')).to be false
      expect(described_class.websearch_requested?('websearch' => '1')).to be false
    end

    it 'is false when TAVILY_API_KEY is missing or blank (fixes DeepSeek empty-string truthy bug)' do
      stub_const('CONFIG', { 'TAVILY_API_KEY' => '' })
      expect(described_class.websearch_requested?('websearch' => true)).to be false
      stub_const('CONFIG', {})
      expect(described_class.websearch_requested?('websearch' => true)).to be false
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

      it "#{filename} computes the websearch flag via TavilyDefinitions.websearch_requested?" do
        content = File.read(File.join(vendors_dir, filename))
        expect(content).to match(/TavilyDefinitions\.websearch_requested\?/)
      end

      it "#{filename} does NOT recompute the websearch flag inline (drift guard)" do
        content = File.read(File.join(vendors_dir, filename))
        expect(content).not_to match(/websearch\s*=\s*.*obj\["websearch"\]\s*==\s*"true"/)
      end
    end
  end
end
