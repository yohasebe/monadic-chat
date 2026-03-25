# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/workflow_viewer_helpers"
require_relative "../../../lib/monadic/utils/system_defaults"

RSpec.describe "API Routes helpers" do
  describe Monadic::Utils::WorkflowViewerHelpers do
    describe ".wv_extract_tools" do
      it "returns all tools with default visibility when no conditionals" do
        settings = {
          progressive_tools: {
            all_tool_names: %w[tool_a tool_b],
            always_visible: %w[tool_a tool_b],
            conditional: []
          }
        }

        result = described_class.wv_extract_tools(settings)

        expect(result.size).to eq(2)
        expect(result[0]).to eq({ name: "tool_a", visibility: "always", unlock_hint: nil })
        expect(result[1]).to eq({ name: "tool_b", visibility: "always", unlock_hint: nil })
      end

      it "applies conditional visibility and unlock hints" do
        settings = {
          progressive_tools: {
            all_tool_names: %w[run_code debug_code],
            always_visible: %w[run_code],
            conditional: [
              { name: "debug_code", visibility: "hidden", unlock_hint: "Ask for debugging" }
            ]
          }
        }

        result = described_class.wv_extract_tools(settings)

        debug_tool = result.find { |t| t[:name] == "debug_code" }
        expect(debug_tool[:visibility]).to eq("hidden")
        expect(debug_tool[:unlock_hint]).to eq("Ask for debugging")
      end

      it "handles string keys (HashWithIndifferentAccess)" do
        settings = {
          "progressive_tools" => {
            "all_tool_names" => %w[fetch_url],
            "conditional" => [
              { "name" => "fetch_url", "visibility" => "on_demand", "unlock_hint" => "Request web access" }
            ]
          }
        }

        result = described_class.wv_extract_tools(settings)

        expect(result.size).to eq(1)
        expect(result[0][:visibility]).to eq("on_demand")
      end

      it "returns empty array when no progressive_tools defined" do
        result = described_class.wv_extract_tools({})
        expect(result).to eq([])
      end
    end

    describe ".wv_extract_agents" do
      it "converts agent hash to string keys and values" do
        settings = { agents: { ai_user: :enabled, second_opinion: "openai" } }

        result = described_class.wv_extract_agents(settings)

        expect(result).to eq({ "ai_user" => "enabled", "second_opinion" => "openai" })
      end

      it "returns empty hash when no agents defined" do
        result = described_class.wv_extract_agents({})
        expect(result).to eq({})
      end

      it "handles string keys" do
        settings = { "agents" => { "context_extractor" => "claude" } }

        result = described_class.wv_extract_agents(settings)

        expect(result).to eq({ "context_extractor" => "claude" })
      end
    end

    describe ".wv_extract_features" do
      it "extracts boolean feature flags from settings" do
        settings = {
          websearch: true,
          monadic: false,
          image: true,
          pdf: false,
          jupyter: true,
          mermaid: false,
          mathjax: true,
          abc: false,
          image_generation: true,
          easy_submit: false,
          auto_speech: false,
          initiate_from_assistant: true
        }

        result = described_class.wv_extract_features(settings)

        expect(result["websearch"]).to be true
        expect(result["monadic"]).to be false
        expect(result["image"]).to be true
        expect(result["jupyter"]).to be true
        expect(result["image_generation"]).to be true
        expect(result["initiate_from_assistant"]).to be true
        expect(result["auto_speech"]).to be false
      end

      it "normalizes pdf capability from pdf_vector_storage" do
        settings = { pdf_vector_storage: true }

        result = described_class.wv_extract_features(settings)

        expect(result["pdf"]).to be true
      end

      it "normalizes pdf capability from pdf_upload" do
        settings = { pdf_upload: true }

        result = described_class.wv_extract_features(settings)

        expect(result["pdf"]).to be true
      end

      it "does not override explicit pdf: true with normalization" do
        settings = { pdf: true, pdf_vector_storage: false }

        result = described_class.wv_extract_features(settings)

        expect(result["pdf"]).to be true
      end

      it "returns all false for empty settings" do
        result = described_class.wv_extract_features({})

        result.each_value do |v|
          expect(v).to be false
        end
      end

      it "handles string keys" do
        settings = { "websearch" => true, "jupyter" => true }

        result = described_class.wv_extract_features(settings)

        expect(result["websearch"]).to be true
        expect(result["jupyter"]).to be true
      end
    end

    describe ".wv_extract_shared_tool_groups" do
      it "returns empty array when no imported_tool_groups" do
        result = described_class.wv_extract_shared_tool_groups({})
        expect(result).to eq([])
      end

      it "extracts group metadata with fallback tool count" do
        settings = {
          imported_tool_groups: [
            { name: "web_browsing", visibility: "always", tool_count: 3 }
          ]
        }

        result = described_class.wv_extract_shared_tool_groups(settings)

        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("web_browsing")
        expect(result[0][:visibility]).to eq("always")
        expect(result[0][:tool_count]).to eq(3)
      end
    end
  end

  describe SystemDefaults do
    describe ".get_default_model" do
      before do
        @orig_extra = ENV['EXTRA_LOGGING']
        @orig_debug = ENV['DEBUG']
        ENV.delete('EXTRA_LOGGING')
        ENV.delete('DEBUG')
      end

      after do
        ENV['EXTRA_LOGGING'] = @orig_extra if @orig_extra
        ENV['DEBUG'] = @orig_debug if @orig_debug
        CONFIG.delete('OPENAI_DEFAULT_MODEL')
        CONFIG.delete('ANTHROPIC_DEFAULT_MODEL')
        CONFIG.delete('GROK_DEFAULT_MODEL')
      end

      it "returns CONFIG value when environment variable is set" do
        CONFIG['OPENAI_DEFAULT_MODEL'] = 'gpt-5'

        result = SystemDefaults.get_default_model('openai')

        expect(result).to eq('gpt-5')
      end

      it "skips empty CONFIG values and falls through to providerDefaults" do
        CONFIG['OPENAI_DEFAULT_MODEL'] = ''

        result = SystemDefaults.get_default_model('openai')

        expect(result).not_to eq('')
      end

      it "normalizes provider name to lowercase" do
        CONFIG['ANTHROPIC_DEFAULT_MODEL'] = 'claude-test'

        expect(SystemDefaults.get_default_model('Anthropic')).to eq('claude-test')
        expect(SystemDefaults.get_default_model('ANTHROPIC')).to eq('claude-test')
      end

      it "maps 'grok' to GROK_DEFAULT_MODEL env var" do
        CONFIG['GROK_DEFAULT_MODEL'] = 'grok-3'

        expect(SystemDefaults.get_default_model('grok')).to eq('grok-3')
      end

      it "maps 'claude' alias to ANTHROPIC env var" do
        CONFIG['ANTHROPIC_DEFAULT_MODEL'] = 'claude-alias-test'

        expect(SystemDefaults.get_default_model('claude')).to eq('claude-alias-test')
      end

      it "returns nil for unknown provider" do
        result = SystemDefaults.get_default_model('unknown_provider')

        expect(result).to be_nil
      end
    end
  end

  describe "AI User Defaults provider key checking" do
    let(:providers_with_keys) do
      {
        'openai' => 'OPENAI_API_KEY',
        'anthropic' => 'ANTHROPIC_API_KEY',
        'gemini' => 'GEMINI_API_KEY',
        'cohere' => 'COHERE_API_KEY',
        'mistral' => 'MISTRAL_API_KEY',
        'deepseek' => 'DEEPSEEK_API_KEY',
        'grok' => 'XAI_API_KEY',
        'perplexity' => 'PERPLEXITY_API_KEY'
      }
    end

    def has_key_for?(provider, config)
      key_name = providers_with_keys[provider]
      !!(config[key_name] && !config[key_name].to_s.strip.empty?)
    end

    it "detects present API keys" do
      config = { 'OPENAI_API_KEY' => 'sk-test123' }
      expect(has_key_for?('openai', config)).to be true
    end

    it "rejects nil keys" do
      config = { 'OPENAI_API_KEY' => nil }
      expect(has_key_for?('openai', config)).to be false
    end

    it "rejects empty string keys" do
      config = { 'OPENAI_API_KEY' => '' }
      expect(has_key_for?('openai', config)).to be false
    end

    it "rejects whitespace-only keys" do
      config = { 'OPENAI_API_KEY' => '   ' }
      expect(has_key_for?('openai', config)).to be false
    end

    it "maps grok to XAI_API_KEY" do
      config = { 'XAI_API_KEY' => 'xai-test' }
      expect(has_key_for?('grok', config)).to be true
    end
  end
end
