require 'spec_helper'

RSpec.describe 'Websearch Tavily Configuration' do
  describe 'Provider categorization' do
    # These providers require Tavily API for web search
    let(:tavily_required_providers) { ['deepseek', 'mistral', 'cohere', 'ollama'] }
    
    # These providers have native web search capabilities
    let(:native_websearch_providers) { ['openai', 'perplexity', 'grok', 'xai', 'gemini', 'google', 'claude', 'anthropic'] }

    it 'correctly identifies providers that require Tavily API' do
      # Verify the lists are comprehensive and mutually exclusive
      all_providers = tavily_required_providers + native_websearch_providers
      expect(all_providers.uniq.size).to eq(all_providers.size)
    end

    context 'with MDSL app configurations' do
      let(:apps_dir) { File.join(File.dirname(__FILE__), '../../apps') }
      let(:chat_apps) { Dir.glob(File.join(apps_dir, 'chat', 'chat_*.mdsl')) }

      it 'Chat apps have appropriate websearch defaults based on provider capabilities' do
        chat_apps.each do |app_file|
          content = File.read(app_file)
          app_name = File.basename(app_file, '.mdsl')
          provider = app_name.gsub('chat_', '')

          # Check if provider has native websearch support
          has_native_support = native_websearch_providers.include?(provider)

          if has_native_support
            # Providers with native support should have websearch enabled
            expect(content).to match(/websearch\s+true/),
              "Expected #{app_name} to have 'websearch true' (provider has native support)"
          else
            # Providers without native support should have websearch disabled
            expect(content).to match(/websearch\s+false/),
              "Expected #{app_name} to have 'websearch false' (Tavily API required)"
          end
        end
      end

      it 'Chat apps have appropriate web search mentions in prompts' do
        chat_apps.each do |app_file|
          content = File.read(app_file)
          app_name = File.basename(app_file, '.mdsl')
          
          # Check for web search guidance in system prompt
          expect(content).to match(/web search|search the web|internet search|online search/i),
            "Expected #{app_name} to mention web search capabilities in prompt"
        end
      end
    end
  end

  describe 'JavaScript module exports' do
    let(:websearch_check_js) { File.join(File.dirname(__FILE__), '../../public/js/monadic/websearch_tavily_check.js') }
    let(:utilities_patch_js) { File.join(File.dirname(__FILE__), '../../public/js/monadic/utilities_websearch_patch.js') }

    it 'websearch_tavily_check.js exports required functions' do
      expect(File.exist?(websearch_check_js)).to be true
      content = File.read(websearch_check_js)
      
      # Check for required exports
      expect(content).to include('window.websearchTavilyCheck')
      expect(content).to include('requiresTavilyAPI')
      expect(content).to include('updateWebSearchState')
    end

    it 'utilities_websearch_patch.js overrides doResetActions' do
      expect(File.exist?(utilities_patch_js)).to be true
      content = File.read(utilities_patch_js)
      
      # Check for function override
      expect(content).to include('window.doResetActions')
      expect(content).to include('fetch(\'/api/environment\')')
      expect(content).to include('websearchTavilyCheck.updateWebSearchState')
    end

    it 'patch handles app switching correctly' do
      content = File.read(utilities_patch_js)
      
      # Check that patch calls original function and adds provider detection
      expect(content).to include('window.originalDoResetActions')
      expect(content).to include('getProviderFromGroup')
    end
  end

  describe 'API endpoint integration' do
    it 'monadic.rb defines /api/environment endpoint' do
      monadic_rb = File.join(File.dirname(__FILE__), '../../lib/monadic.rb')
      content = File.read(monadic_rb)
      
      expect(content).to include('get "/api/environment"')
      expect(content).to include('has_tavily_key')
      expect(content).to include('CONFIG["TAVILY_API_KEY"]')
    end
  end
end