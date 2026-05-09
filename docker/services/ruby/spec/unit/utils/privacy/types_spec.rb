# frozen_string_literal: true

require 'monadic/utils/privacy/types'

RSpec.describe Monadic::Utils::Privacy do
  describe Monadic::Utils::Privacy::RawMessage do
    subject(:raw) { described_class.new("田中様、こんにちは。", "user", { ts: 100 }) }

    it "is not safe to send to LLM" do
      expect(raw.safe_for_llm?).to be false
    end

    it "transitions to MaskedMessage via #to_masked" do
      masked = raw.to_masked("<<PERSON_1>>様、こんにちは。", [{ "placeholder" => "<<PERSON_1>>" }])
      expect(masked).to be_a(Monadic::Utils::Privacy::MaskedMessage)
      expect(masked.safe_for_llm?).to be true
      expect(masked.text).to include("<<PERSON_1>>")
      expect(masked.meta[:privacy][:masked]).to be true
      expect(masked.meta[:privacy][:original_length]).to eq(raw.text.length)
    end

    it "preserves the original ts metadata across transition" do
      masked = raw.to_masked("x", [])
      expect(masked.meta[:ts]).to eq(100)
    end
  end

  describe Monadic::Utils::Privacy::MaskedResponse do
    subject(:resp) { described_class.new("Hi <<PERSON_1>>!", { source: "openai" }) }

    it "transitions to RestoredResponse via #to_restored" do
      restored = resp.to_restored("Hi Alice!", [])
      expect(restored).to be_a(Monadic::Utils::Privacy::RestoredResponse)
      expect(restored.safe_for_user?).to be true
      expect(restored.text).to eq("Hi Alice!")
      expect(restored.meta[:privacy][:restored]).to be true
      expect(restored.meta[:privacy][:missing_placeholders]).to eq([])
    end

    it "carries missing placeholders through restoration" do
      restored = resp.to_restored("Hi Alice and <<PERSON_2>>", ["<<PERSON_2>>"])
      expect(restored.meta[:privacy][:missing_placeholders]).to eq(["<<PERSON_2>>"])
    end
  end
end
