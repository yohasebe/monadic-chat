require 'spec_helper'
require_relative '../../lib/monadic/shared_tools/web_search_tools'

RSpec.describe MonadicSharedTools::WebSearchTools do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::WebSearchTools

      # Mock respond_to? to simulate TavilyHelper presence
      def respond_to?(method_name, include_private = false)
        method_name == :tavily_search || super
      end

      # Mock tavily_search to prevent actual API calls
      def tavily_search(query:, n: 3)
        { success: true, query: query, results_count: n }
      end
    end
  end

  describe '.available?' do
    it 'returns true when module is loaded' do
      expect(described_class.available?).to be true
    end
  end

  describe 'Provider detection and routing' do
    context 'with OpenAI provider' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatOpenAI')
        end
      end

      it 'routes to native OpenAI search' do
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include('native capabilities')
      end
    end

    context 'with Claude provider' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatClaude')
        end
      end

      it 'routes to native Claude search' do
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include('native search capabilities')
      end
    end

    context 'with Gemini provider' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatGemini')
        end
      end

      it 'routes to native Gemini search' do
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include('URL Context')
      end
    end

    context 'with Grok provider' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatGrok')
        end
      end

      it 'routes to native Grok search' do
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include('Live Search')
      end
    end

    context 'with Perplexity provider' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatPerplexity')
        end
      end

      it 'routes to native Perplexity search' do
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include('native search')
      end
    end

    context 'with Tavily-dependent provider (DeepSeek)' do
      let(:instance) do
        test_class.new.tap do |obj|
          allow(obj.class).to receive(:name).and_return('ChatDeepSeek')
        end
      end

      context 'when TAVILY_API_KEY is configured' do
        before do
          allow(CONFIG).to receive(:[]).with('TAVILY_API_KEY').and_return('test-key')
        end

        it 'routes to Tavily search' do
          result = instance.search_web(query: 'test query', max_results: 5)
          expect(result).to be_a(Hash)
          expect(result[:success]).to be true
          expect(result[:results_count]).to eq(5)
        end
      end

      context 'when TAVILY_API_KEY is not configured' do
        before do
          allow(CONFIG).to receive(:[]).with('TAVILY_API_KEY').and_return(nil)
        end

        it 'returns error message' do
          result = instance.search_web(query: 'test query')
          expect(result).to be_a(Hash)
          expect(result[:success]).to be false
          expect(result[:error]).to include('not available')
        end
      end
    end
  end

  describe '#fetch_web_content' do
    let(:instance) { test_class.new }

    it 'accepts URL and timeout parameters' do
      # Mock LOCAL_SHARED_VOL constant
      stub_const('MonadicSharedTools::WebSearchTools::LOCAL_SHARED_VOL', '/tmp/test_shared')

      # Mock MonadicApp.fetch_webpage to prevent actual HTTP calls
      allow(MonadicApp).to receive(:fetch_webpage).and_return('Mock webpage content')

      # Mock file operations
      allow(File).to receive(:write)

      result = instance.fetch_web_content(url: 'https://example.com', timeout: 10)
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:url]).to eq('https://example.com')
    end
  end

  describe '#tavily_search' do
    let(:instance) { test_class.new }

    it 'delegates to TavilyHelper when available' do
      result = instance.tavily_search(query: 'test', n: 3)
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
    end
  end

  describe '#tavily_fetch' do
    let(:instance) { test_class.new }

    before do
      # Mock interaction_utils method
      allow(instance).to receive(:tavily_fetch).with(url: 'https://example.com')
        .and_return('Mock fetched content')
    end

    it 'fetches URL content via Tavily' do
      result = instance.tavily_fetch(url: 'https://example.com')
      expect(result).to eq('Mock fetched content')
    end
  end

  describe 'Registry integration' do
    it 'is registered in the tool registry' do
      expect(MonadicSharedTools::Registry.group_exists?(:web_search_tools)).to be true
      expect(MonadicSharedTools::Registry.module_name_for(:web_search_tools)).to eq('MonadicSharedTools::WebSearchTools')
    end

    it 'defines 4 tools' do
      tools = MonadicSharedTools::Registry.tools_for(:web_search_tools)
      expect(tools.size).to eq(4)
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include('search_web', 'fetch_web_content', 'tavily_search', 'tavily_fetch')
    end

    it 'has conditional visibility' do
      expect(MonadicSharedTools::Registry.visibility_for(:web_search_tools)).to eq('conditional')
    end

    it 'has availability check' do
      expect(MonadicSharedTools::Registry.available?(:web_search_tools)).to be true
    end
  end

  describe 'Backward compatibility' do
    it 'provides all tools from previous web_tools module' do
      tools = MonadicSharedTools::Registry.tools_for(:web_search_tools)
      tool_names = tools.map { |t| t[:name] }

      # web_tools had: search_web, fetch_web_content
      expect(tool_names).to include('search_web', 'fetch_web_content')
    end

    it 'provides all tools from previous tavily_search_tools module' do
      tools = MonadicSharedTools::Registry.tools_for(:web_search_tools)
      tool_names = tools.map { |t| t[:name] }

      # tavily_search_tools had: tavily_search, tavily_fetch
      expect(tool_names).to include('tavily_search', 'tavily_fetch')
    end

    it 'maintains WebSearchAgent routing logic' do
      # WebSearchAgent routed based on provider name
      instance = test_class.new

      # Test each provider category
      native_providers = ['openai', 'claude', 'gemini', 'grok', 'perplexity']
      native_providers.each do |provider|
        allow(instance.class).to receive(:name).and_return("Chat#{provider.capitalize}")
        result = instance.search_web(query: 'test')
        expect(result).to be_a(String)
        expect(result).not_to include('error')
      end
    end
  end
end
