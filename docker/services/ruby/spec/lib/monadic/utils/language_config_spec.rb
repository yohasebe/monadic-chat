# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/language_config"

RSpec.describe Monadic::Utils::LanguageConfig do
  describe ".display_name" do
    it "returns native name with English in parentheses for non-English languages" do
      expect(described_class.display_name("ja")).to eq("日本語 (Japanese)")
      expect(described_class.display_name("zh")).to eq("中文 (Chinese)")
      expect(described_class.display_name("fr")).to eq("Français (French)")
    end

    it "returns only native name for English" do
      expect(described_class.display_name("en")).to eq("English")
    end

    it "returns only native name for auto" do
      expect(described_class.display_name("auto")).to eq("Automatic")
    end

    it "returns 'Unknown' for invalid language codes" do
      expect(described_class.display_name("xyz")).to eq("Unknown")
    end
  end

  describe ".system_prompt_for_language" do
    it "returns language instruction for valid language codes" do
      prompt = described_class.system_prompt_for_language("ja")
      expect(prompt).to include("Please respond in Japanese")
      expect(prompt).to include("If the user writes in Japanese")
    end

    it "returns empty string for 'auto'" do
      expect(described_class.system_prompt_for_language("auto")).to eq("")
    end

    it "returns empty string for nil" do
      expect(described_class.system_prompt_for_language(nil)).to eq("")
    end

    it "returns empty string for unknown language codes" do
      expect(described_class.system_prompt_for_language("xyz")).to eq("")
    end
  end

  describe ".stt_language_code" do
    it "returns the language code for valid languages" do
      expect(described_class.stt_language_code("ja")).to eq("ja")
      expect(described_class.stt_language_code("en")).to eq("en")
    end

    it "returns nil for 'auto'" do
      expect(described_class.stt_language_code("auto")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.stt_language_code(nil)).to be_nil
    end
  end

  describe ".tts_language_code" do
    context "with OpenAI provider" do
      it "returns language code for valid languages" do
        expect(described_class.tts_language_code("ja", "openai")).to eq("ja")
      end

      it "returns 'auto' for auto setting" do
        expect(described_class.tts_language_code("auto", "openai")).to eq("auto")
      end
    end

    context "with ElevenLabs provider" do
      it "returns language code for valid languages" do
        expect(described_class.tts_language_code("ja", "elevenlabs")).to eq("ja")
        expect(described_class.tts_language_code("ja", "elevenlabs-flash")).to eq("ja")
        expect(described_class.tts_language_code("ja", "elevenlabs-multilingual")).to eq("ja")
      end

      it "returns 'auto' for auto setting" do
        expect(described_class.tts_language_code("auto", "elevenlabs")).to eq("auto")
      end
    end

    context "with Gemini provider" do
      it "always returns 'auto' regardless of language" do
        expect(described_class.tts_language_code("ja", "gemini")).to eq("auto")
        expect(described_class.tts_language_code("en", "gemini")).to eq("auto")
        expect(described_class.tts_language_code("auto", "gemini")).to eq("auto")
      end
    end

    context "with unknown provider" do
      it "returns the language code as-is" do
        expect(described_class.tts_language_code("ja", "unknown")).to eq("ja")
        expect(described_class.tts_language_code("auto", "unknown")).to eq("auto")
      end
    end
  end

  describe ".tts_supports_language?" do
    it "returns true for providers that support explicit language" do
      expect(described_class.tts_supports_language?("openai")).to be true
      expect(described_class.tts_supports_language?("elevenlabs")).to be true
      expect(described_class.tts_supports_language?("elevenlabs-flash")).to be true
      expect(described_class.tts_supports_language?("elevenlabs-multilingual")).to be true
    end

    it "returns false for providers that don't support explicit language" do
      expect(described_class.tts_supports_language?("gemini")).to be false
      expect(described_class.tts_supports_language?("unknown")).to be false
    end
  end

  describe ".all_languages" do
    it "returns an array of language hashes" do
      languages = described_class.all_languages
      expect(languages).to be_an(Array)
      expect(languages).not_to be_empty
    end

    it "includes auto as the first language" do
      first_lang = described_class.all_languages.first
      expect(first_lang[:code]).to eq("auto")
      expect(first_lang[:display]).to eq("Automatic")
    end

    it "includes major languages" do
      codes = described_class.all_languages.map { |l| l[:code] }
      expect(codes).to include("en", "ja", "zh", "es", "fr", "de")
    end

    it "has correct structure for each language" do
      described_class.all_languages.each do |lang|
        expect(lang).to have_key(:code)
        expect(lang).to have_key(:display)
        expect(lang).to have_key(:english)
        expect(lang).to have_key(:native)
      end
    end
  end

  describe "LANGUAGES constant" do
    it "contains 58 languages including auto" do
      expect(described_class::LANGUAGES.size).to eq(58)
    end

    it "has correct structure for each language entry" do
      described_class::LANGUAGES.each do |code, info|
        expect(code).to be_a(String)
        expect(info).to have_key(:english)
        expect(info).to have_key(:native)
        expect(info[:english]).to be_a(String)
        expect(info[:native]).to be_a(String)
      end
    end
  end
end