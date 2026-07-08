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
    it 'returns true when a Tavily key is configured' do
      original = CONFIG["TAVILY_API_KEY"]
      CONFIG["TAVILY_API_KEY"] ||= "test-key"
      expect(described_class.available?).to be true
    ensure
      original.nil? ? CONFIG.delete("TAVILY_API_KEY") : CONFIG["TAVILY_API_KEY"] = original
    end
  end

  describe 'Provider detection and routing' do
    context 'when TAVILY_API_KEY is configured' do
      before do
        allow(CONFIG).to receive(:[]).with('TAVILY_API_KEY').and_return('test-key')
      end

      # A real search backend is preferred for every provider. Native search
      # runs on the provider side and does not route through this function, so
      # an actual search_web call always wants concrete results.
      %w[openai claude gemini grok].each do |provider|
        it "routes #{provider} to Tavily instead of a native placeholder" do
          instance = test_class.new
          allow(instance.class).to receive(:name).and_return("Chat#{provider.capitalize}")
          result = instance.search_web(query: 'test query', max_results: 5)
          expect(result).to be_a(Hash)
          expect(result[:success]).to be true
          expect(result[:results_count]).to eq(5)
        end
      end
    end

    context 'when TAVILY_API_KEY is NOT configured' do
      before do
        allow(CONFIG).to receive(:[]).with('TAVILY_API_KEY').and_return(nil)
      end

      it 'returns a provider-agnostic native-search notice for native providers' do
        instance = test_class.new
        allow(instance.class).to receive(:name).and_return('ChatGrok')
        result = instance.search_web(query: 'test query')
        expect(result).to be_a(String)
        expect(result).to include("native search")
        # Regression: the old code hardcoded "Claude" for every non-OpenAI
        # provider, mislabeling Grok/Gemini. The message must not name a
        # specific provider it cannot verify.
        expect(result).not_to include('Claude')
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
      original = CONFIG["TAVILY_API_KEY"]
      CONFIG["TAVILY_API_KEY"] ||= "test-key"
      expect(MonadicSharedTools::Registry.available?(:web_search_tools)).to be true
    ensure
      original.nil? ? CONFIG.delete("TAVILY_API_KEY") : CONFIG["TAVILY_API_KEY"] = original
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
      # Without a Tavily key, native providers fall back to the native-search
      # notice string (never an error), regardless of provider name.
      allow(CONFIG).to receive(:[]).with('TAVILY_API_KEY').and_return(nil)
      instance = test_class.new

      native_providers = ['openai', 'claude', 'gemini', 'grok']
      native_providers.each do |provider|
        allow(instance.class).to receive(:name).and_return("Chat#{provider.capitalize}")
        result = instance.search_web(query: 'test')
        expect(result).to be_a(String)
        expect(result).not_to include('error')
      end
    end
  end
end
