# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/boolean_parser"

RSpec.describe BooleanParser do
  describe ".parse" do
    context "with boolean values" do
      it "returns true for true" do
        expect(described_class.parse(true)).to eq(true)
      end
      
      it "returns false for false" do
        expect(described_class.parse(false)).to eq(false)
      end
    end
    
    context "with string values" do
      it "returns true for 'true'" do
        expect(described_class.parse("true")).to eq(true)
      end
      
      it "returns false for 'false'" do
        expect(described_class.parse("false")).to eq(false)
      end
      
      it "returns true for '1'" do
        expect(described_class.parse("1")).to eq(true)
      end
      
      it "returns false for '0'" do
        expect(described_class.parse("0")).to eq(false)
      end
      
      it "returns true for 'yes'" do
        expect(described_class.parse("yes")).to eq(true)
      end
      
      it "returns false for 'no'" do
        expect(described_class.parse("no")).to eq(false)
      end
      
      it "is case insensitive" do
        expect(described_class.parse("TRUE")).to eq(true)
        expect(described_class.parse("False")).to eq(false)
      end
      
      it "handles whitespace" do
        expect(described_class.parse(" true ")).to eq(true)
        expect(described_class.parse("  false  ")).to eq(false)
      end
    end
    
    context "with numeric values" do
      it "returns true for 1" do
        expect(described_class.parse(1)).to eq(true)
      end
      
      it "returns false for 0" do
        expect(described_class.parse(0)).to eq(false)
      end
      
      it "returns true for non-zero numbers" do
        expect(described_class.parse(42)).to eq(true)
        expect(described_class.parse(-1)).to eq(true)
      end
    end
    
    context "with nil" do
      it "returns false for nil" do
        expect(described_class.parse(nil)).to eq(false)
      end
    end
  end
  
  describe ".parse_strict" do
    it "returns nil for invalid values" do
      expect(described_class.parse_strict("maybe")).to be_nil
      expect(described_class.parse_strict("random")).to be_nil
      expect(described_class.parse_strict(42)).to be_nil
    end
    
    it "only accepts specific valid values" do
      expect(described_class.parse_strict(true)).to eq(true)
      expect(described_class.parse_strict("true")).to eq(true)
      expect(described_class.parse_strict("1")).to eq(true)
      expect(described_class.parse_strict(1)).to eq(true)
      expect(described_class.parse_strict(false)).to eq(false)
      expect(described_class.parse_strict("false")).to eq(false)
      expect(described_class.parse_strict("0")).to eq(false)
      expect(described_class.parse_strict(0)).to eq(false)
    end
  end
  
  describe ".parse_hash" do
    it "converts boolean fields in a hash" do
      input = {
        "websearch" => "true",
        "auto_speech" => "false",
        "monadic" => true,
        "temperature" => 0.7,
        "model" => "gpt-4"
      }
      
      result = described_class.parse_hash(input)
      
      expect(result["websearch"]).to eq(true)
      expect(result["auto_speech"]).to eq(false)
      expect(result["monadic"]).to eq(true)
      expect(result["temperature"]).to eq(0.7)
      expect(result["model"]).to eq("gpt-4")
    end
    
    it "accepts specific fields to parse" do
      input = {
        "custom_flag" => "true",
        "other_value" => "true"
      }
      
      result = described_class.parse_hash(input, ["custom_flag"])
      
      expect(result["custom_flag"]).to eq(true)
      expect(result["other_value"]).to eq("true") # Not parsed
    end
  end
end