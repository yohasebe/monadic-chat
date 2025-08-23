# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/language_config"

RSpec.describe Monadic::Utils::LanguageConfig do
  describe "RTL language support" do
    describe ".rtl_language?" do
      context "with RTL languages" do
        it "returns true for Arabic" do
          expect(described_class.rtl_language?("ar")).to be true
        end

        it "returns true for Hebrew" do
          expect(described_class.rtl_language?("he")).to be true
        end

        it "returns true for Persian/Farsi" do
          expect(described_class.rtl_language?("fa")).to be true
        end

        it "returns true for Urdu" do
          expect(described_class.rtl_language?("ur")).to be true
        end
      end

      context "with LTR languages" do
        it "returns false for English" do
          expect(described_class.rtl_language?("en")).to be false
        end

        it "returns false for Japanese" do
          expect(described_class.rtl_language?("ja")).to be false
        end

        it "returns false for Chinese" do
          expect(described_class.rtl_language?("zh")).to be false
        end

        it "returns false for Spanish" do
          expect(described_class.rtl_language?("es")).to be false
        end

        it "returns false for auto" do
          expect(described_class.rtl_language?("auto")).to be false
        end

        it "returns false for unknown language codes" do
          expect(described_class.rtl_language?("xyz")).to be false
        end

        it "returns false for nil" do
          expect(described_class.rtl_language?(nil)).to be false
        end
      end
    end

    describe ".text_direction" do
      context "with RTL languages" do
        it "returns 'rtl' for Arabic" do
          expect(described_class.text_direction("ar")).to eq("rtl")
        end

        it "returns 'rtl' for Hebrew" do
          expect(described_class.text_direction("he")).to eq("rtl")
        end

        it "returns 'rtl' for Persian" do
          expect(described_class.text_direction("fa")).to eq("rtl")
        end

        it "returns 'rtl' for Urdu" do
          expect(described_class.text_direction("ur")).to eq("rtl")
        end
      end

      context "with LTR languages" do
        it "returns 'ltr' for English" do
          expect(described_class.text_direction("en")).to eq("ltr")
        end

        it "returns 'ltr' for Japanese" do
          expect(described_class.text_direction("ja")).to eq("ltr")
        end

        it "returns 'ltr' for auto" do
          expect(described_class.text_direction("auto")).to eq("ltr")
        end

        it "returns 'ltr' for unknown codes" do
          expect(described_class.text_direction("xyz")).to eq("ltr")
        end
      end
    end

    describe "RTL languages in LANGUAGES constant" do
      it "includes all RTL languages in the main language list" do
        rtl_codes = ["ar", "he", "fa", "ur"]
        rtl_codes.each do |code|
          expect(described_class::LANGUAGES).to have_key(code)
        end
      end

      it "has correct native names for RTL languages" do
        expect(described_class::LANGUAGES["ar"][:native]).to eq("العربية")
        expect(described_class::LANGUAGES["he"][:native]).to eq("עברית")
        expect(described_class::LANGUAGES["fa"][:native]).to eq("فارسی")
        expect(described_class::LANGUAGES["ur"][:native]).to eq("اردو")
      end

      it "has correct English names for RTL languages" do
        expect(described_class::LANGUAGES["ar"][:english]).to eq("Arabic")
        expect(described_class::LANGUAGES["he"][:english]).to eq("Hebrew")
        expect(described_class::LANGUAGES["fa"][:english]).to eq("Persian")
        expect(described_class::LANGUAGES["ur"][:english]).to eq("Urdu")
      end
    end

    describe "integration with display_name" do
      it "correctly displays RTL language names" do
        expect(described_class.display_name("ar")).to eq("العربية (Arabic)")
        expect(described_class.display_name("he")).to eq("עברית (Hebrew)")
        expect(described_class.display_name("fa")).to eq("فارسی (Persian)")
        expect(described_class.display_name("ur")).to eq("اردو (Urdu)")
      end
    end
  end
end