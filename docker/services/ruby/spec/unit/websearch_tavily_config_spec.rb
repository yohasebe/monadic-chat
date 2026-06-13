require 'spec_helper'

RSpec.describe 'Websearch Tavily Configuration' do
  describe 'Provider categorization' do
    # These providers require Tavily API for web search
    let(:tavily_required_providers) { ['deepseek', 'mistral', 'cohere', 'ollama'] }
    
    # These providers have native web search capabilities
    let(:native_websearch_providers) { ['openai', 'grok', 'xai', 'gemini', 'google', 'claude', 'anthropic'] }

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
    let(:utilities_js) { File.join(File.dirname(__FILE__), '../../public/js/monadic/utilities.js') }

    it 'websearch_tavily_check.js exports required functions' do
      expect(File.exist?(websearch_check_js)).to be true
      content = File.read(websearch_check_js)

      # Check for required exports
      expect(content).to include('window.websearchTavilyCheck')
      expect(content).to include('requiresTavilyAPI')
      expect(content).to include('updateWebSearchState')
    end

    it 'doResetActions checks Tavily availability (merged from former websearch patch)' do
      expect(File.exist?(utilities_js)).to be true
      content = File.read(utilities_js)

      expect(content).to include('fetch(\'/api/environment\')')
      expect(content).to include('websearchTavilyCheck.updateWebSearchState')
      expect(content).to include('getProviderFromGroup')
    end
  end

  describe 'API endpoint integration' do
    it 'api_routes.rb defines /api/environment endpoint' do
      api_routes_rb = File.join(File.dirname(__FILE__), '../../lib/monadic/routes/api_routes.rb')
      content = File.read(api_routes_rb)

      expect(content).to include('get "/api/environment"')
      expect(content).to include('has_tavily_key')
      expect(content).to include('CONFIG["TAVILY_API_KEY"]')
    end
  end

  describe 'Provider-level proactive Tavily gate' do
    # Each Tavily-fallback provider's helper must AND-gate the
    # `websearch` decision on CONFIG["TAVILY_API_KEY"] before
    # registering tavily_* tools or augmenting the system prompt.
    # Without the gate, a user without the API key but with the UI
    # websearch toggle on gets a "Bearer token not found" tool error
    # mid-conversation instead of a silent fall-through (Cohere /
    # DeepSeek's behaviour). Structural spec — catches accidental
    # removal of the gate during future refactors.
    let(:vendors_dir) do
      File.join(File.dirname(__FILE__), '../../lib/monadic/adapters/vendors')
    end

    {
      'cohere_helper.rb' => 'CohereHelper',
      'deepseek_helper.rb' => 'DeepSeekHelper',
      'mistral_helper.rb' => 'MistralHelper',
      'ollama_helper.rb' => 'OllamaHelper'
    }.each do |filename, label|
      it "#{label} gates websearch on TAVILY_API_KEY presence" do
        path = File.join(vendors_dir, filename)
        expect(File.exist?(path)).to be(true), "#{filename}: helper file missing"
        content = File.read(path)

        # Locate the assignment(s) that set the `websearch` boolean used
        # to decide tavily_* tool registration. The pattern of
        # interest is "this assignment derives websearch from
        # obj['websearch'] AND from a TAVILY_API_KEY check". The check
        # can take two shapes:
        #   (a) inlined: `websearch = CONFIG["TAVILY_API_KEY"] &&
        #       (obj["websearch"] == "true" || ...)`
        #   (b) via helper variable: `has_tavily = !!CONFIG[...]; ... ;
        #       websearch = has_tavily && requested_web` where
        #       `requested_web` is derived from `obj["websearch"]`.
        #
        # Both are acceptable. Verify by scanning a window of ~5 lines
        # ending at each `websearch = ...obj["websearch"]...` site
        # (or, for the helper-variable shape, the line that mentions
        # `has_tavily`). Either pattern must include TAVILY_API_KEY in
        # the same window.
        # Use obj["websearch"] sites as the anchor (every gate must
        # ultimately consume the UI toggle from `obj`). For each
        # occurrence, scan a window of ~5 lines before AND after for
        # both a `websearch =` assignment and the TAVILY_API_KEY
        # check (direct or via `has_tavily`). Multi-line tolerant:
        # the Mistral assignment intentionally wraps across two lines
        # so the gate predicate is visually separated from the source
        # of truth.
        obj_websearch_sites = content.lines.each_with_index.select do |line, _|
          line.include?('obj["websearch"]')
        end

        expect(obj_websearch_sites).not_to be_empty,
          "#{filename}: no obj[\"websearch\"] references found"

        gating_site_found = obj_websearch_sites.any? do |_line, idx|
          window_start = [idx - 5, 0].max
          window_end = [idx + 5, content.lines.size - 1].min
          window = content.lines[window_start..window_end].join
          window.match?(/\bwebsearch\s*=/) &&
            window.match?(/TAVILY_API_KEY|\bhas_tavily\b/)
        end

        expect(gating_site_found).to be(true),
          "#{filename}: at least one obj[\"websearch\"] site must sit within 5 lines of both `websearch =` and TAVILY_API_KEY (or `has_tavily` helper)"
      end
    end
  end
end