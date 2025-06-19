# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/monadic/utils/config_helper"

RSpec.describe ConfigHelper do
  before(:each) do
    # Save original values
    @original_env = {}
    @original_config = defined?(CONFIG) ? CONFIG.dup : nil

    # Clear test-related ENV variables
    %w[TEST_KEY OPENAI_API_KEY ANTHROPIC_API_KEY AI_USER_MAX_TOKENS
       GEMINI_API_KEY MISTRAL_API_KEY COHERE_API_KEY PERPLEXITY_API_KEY
       DEEPSEEK_API_KEY XAI_API_KEY ELEVENLABS_API_KEY].each do |key|
      @original_env[key] = ENV.fetch(key, nil)
      ENV.delete(key)
    end

    # Set up test CONFIG
    stub_const("CONFIG", {})
  end

  after(:each) do
    # Restore original values
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end

    stub_const("CONFIG", @original_config) if @original_config
  end

  describe ".get_config" do
    it "returns ENV value when set" do
      ENV["TEST_KEY"] = "env_value"
      CONFIG["TEST_KEY"] = "config_value"

      expect(ConfigHelper.get_config("TEST_KEY")).to eq("env_value")
    end

    it "returns CONFIG value when ENV not set" do
      CONFIG["TEST_KEY"] = "config_value"

      expect(ConfigHelper.get_config("TEST_KEY")).to eq("config_value")
    end

    it "returns default when neither ENV nor CONFIG set" do
      expect(ConfigHelper.get_config("TEST_KEY", "default")).to eq("default")
    end

    it "returns nil when no default provided" do
      expect(ConfigHelper.get_config("TEST_KEY")).to be_nil
    end

    it "ignores empty ENV values" do
      ENV["TEST_KEY"] = ""
      CONFIG["TEST_KEY"] = "config_value"

      expect(ConfigHelper.get_config("TEST_KEY")).to eq("config_value")
    end

    it "ignores empty CONFIG values" do
      CONFIG["TEST_KEY"] = ""

      expect(ConfigHelper.get_config("TEST_KEY", "default")).to eq("default")
    end
  end

  describe ".get_api_key" do
    context "OpenAI (maintains backward compatibility)" do
      it "prioritizes ENV over CONFIG" do
        ENV["OPENAI_API_KEY"] = "env_key"
        CONFIG["OPENAI_API_KEY"] = "config_key"

        expect(ConfigHelper.get_api_key("openai")).to eq("env_key")
      end

      it "falls back to CONFIG when ENV not set" do
        CONFIG["OPENAI_API_KEY"] = "config_key"

        expect(ConfigHelper.get_api_key("openai")).to eq("config_key")
      end
    end

    context "Other providers (standard pattern)" do
      it "prioritizes ENV over CONFIG for Anthropic" do
        ENV["ANTHROPIC_API_KEY"] = "env_key"
        CONFIG["ANTHROPIC_API_KEY"] = "config_key"

        expect(ConfigHelper.get_api_key("anthropic")).to eq("env_key")
        expect(ConfigHelper.get_api_key("claude")).to eq("env_key")
      end

      it "handles all supported providers" do
        providers = {
          "gemini" => "GEMINI_API_KEY",
          "mistral" => "MISTRAL_API_KEY",
          "cohere" => "COHERE_API_KEY",
          "perplexity" => "PERPLEXITY_API_KEY",
          "deepseek" => "DEEPSEEK_API_KEY",
          "grok" => "XAI_API_KEY",
          "xai" => "XAI_API_KEY",
          "elevenlabs" => "ELEVENLABS_API_KEY"
        }

        providers.each do |provider, key|
          CONFIG[key] = "test_#{provider}_key"
          expect(ConfigHelper.get_api_key(provider)).to eq("test_#{provider}_key")
        end
      end
    end

    it "returns nil for unknown provider" do
      expect(ConfigHelper.get_api_key("unknown")).to be_nil
    end
  end

  describe ".distributed_mode?" do
    it "returns true when set to 'on'" do
      CONFIG["DISTRIBUTED_MODE"] = "on"
      expect(ConfigHelper.distributed_mode?).to be true
    end

    it "returns false when set to 'off'" do
      CONFIG["DISTRIBUTED_MODE"] = "off"
      expect(ConfigHelper.distributed_mode?).to be false
    end

    it "returns false by default" do
      expect(ConfigHelper.distributed_mode?).to be false
    end

    it "handles case insensitively" do
      CONFIG["DISTRIBUTED_MODE"] = "ON"
      expect(ConfigHelper.distributed_mode?).to be true
    end
  end

  describe ".extra_logging?" do
    it "returns true when set to 'true'" do
      CONFIG["EXTRA_LOGGING"] = "true"
      expect(ConfigHelper.extra_logging?).to be true
    end

    it "returns false when set to 'false'" do
      CONFIG["EXTRA_LOGGING"] = "false"
      expect(ConfigHelper.extra_logging?).to be false
    end

    it "returns false by default" do
      expect(ConfigHelper.extra_logging?).to be false
    end
  end

  describe ".ai_user_max_tokens" do
    it "returns integer value from CONFIG" do
      CONFIG["AI_USER_MAX_TOKENS"] = "3000"
      expect(ConfigHelper.ai_user_max_tokens).to eq(3000)
    end

    it "returns default 2000 when not set" do
      expect(ConfigHelper.ai_user_max_tokens).to eq(2000)
    end

    it "prioritizes ENV over CONFIG" do
      ENV["AI_USER_MAX_TOKENS"] = "4000"
      CONFIG["AI_USER_MAX_TOKENS"] = "3000"
      expect(ConfigHelper.ai_user_max_tokens).to eq(4000)
    end
  end

  describe ".ai_user_model" do
    it "returns value from CONFIG" do
      CONFIG["AI_USER_MODEL"] = "gpt-4"
      expect(ConfigHelper.ai_user_model).to eq("gpt-4")
    end

    it "returns default when not set" do
      expect(ConfigHelper.ai_user_model).to eq("gpt-4.1-mini")
    end
  end

  describe ".jupyter_port" do
    it "returns value from CONFIG" do
      CONFIG["JUPYTER_PORT"] = "9000"
      expect(ConfigHelper.jupyter_port).to eq("9000")
    end

    it "returns default 8889 when not set" do
      expect(ConfigHelper.jupyter_port).to eq("8889")
    end
  end
end
