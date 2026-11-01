# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/tts_provider"

RSpec.describe Monadic::Utils::TtsProvider do
  describe ".api_key_name" do
    it "names the key of each server-side provider" do
      expect(described_class.api_key_name("openai")).to eq("OPENAI_API_KEY")
      expect(described_class.api_key_name("elevenlabs")).to eq("ELEVENLABS_API_KEY")
      expect(described_class.api_key_name("gemini")).to eq("GEMINI_API_KEY")
    end

    it "is nil for an unknown provider" do
      expect(described_class.api_key_name("other")).to be_nil
      expect(described_class.api_key_name(nil)).to be_nil
    end
  end

  describe ".api_key" do
    it "takes the first source that has the key" do
      first = { "GEMINI_API_KEY" => "from-first" }
      second = { "GEMINI_API_KEY" => "from-second" }
      expect(described_class.api_key("gemini", first, second)).to eq("from-first")
    end

    it "falls back when the first source has no value or a blank one" do
      second = { "GEMINI_API_KEY" => "from-second" }
      expect(described_class.api_key("gemini", {}, second)).to eq("from-second")
      expect(described_class.api_key("gemini", { "GEMINI_API_KEY" => "  " }, second)).to eq("from-second")
    end

    it "accepts a lambda as a source" do
      source = ->(name) { name == "OPENAI_API_KEY" ? "from-lambda" : nil }
      expect(described_class.api_key("openai", source)).to eq("from-lambda")
    end

    it "is nil when no source has a value" do
      expect(described_class.api_key("elevenlabs", {}, { "ELEVENLABS_API_KEY" => "" })).to be_nil
    end

    it "is nil for an unknown provider, whatever the sources hold" do
      expect(described_class.api_key("other", { "OTHER_API_KEY" => "x" })).to be_nil
    end
  end
end
