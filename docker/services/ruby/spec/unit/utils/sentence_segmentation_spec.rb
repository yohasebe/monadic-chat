# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/utils/websocket"

RSpec.describe WebSocketHelper do
  describe ".segment_sentences" do
    context "with English text" do
      it "segments sentences correctly" do
        text = "Hello world. This is a test. How are you?"
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(3)
        expect(segments[0]).to eq("Hello world.")
        expect(segments[1]).to eq("This is a test.")
        expect(segments[2]).to eq("How are you?")
      end
    end

    context "with Arabic text (RTL)" do
      it "segments sentences correctly" do
        text = "مرحبا بالعالم. هذا اختبار. كيف حالك؟"
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(3)
        expect(segments[0]).to include("مرحبا")
        expect(segments[1]).to include("اختبار")
        expect(segments[2]).to include("حالك")
      end
    end

    context "with Hebrew text (RTL)" do
      it "segments sentences correctly" do
        text = "שלום עולם. זה מבחן. מה שלומך?"
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(3)
        expect(segments[0]).to include("שלום")
        expect(segments[1]).to include("מבחן")
        expect(segments[2]).to include("שלומך")
      end
    end

    context "with Persian text (RTL)" do
      it "segments sentences correctly" do
        text = "سلام دنیا. این یک آزمایش است. حال شما چطور است؟"
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(3)
        expect(segments[0]).to include("سلام")
        expect(segments[1]).to include("آزمایش")
        expect(segments[2]).to include("چطور")
      end
    end

    context "with mixed LTR/RTL text" do
      it "segments sentences correctly" do
        text = "Hello! مرحبا. This is mixed."
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(3)
      end
    end

    context "with empty or nil input" do
      it "returns empty array for nil" do
        expect(described_class.segment_sentences(nil)).to eq([])
      end

      it "returns empty array for empty string" do
        expect(described_class.segment_sentences("")).to eq([])
      end
    end

    context "with single sentence" do
      it "returns array with one element" do
        text = "This is a single sentence without ending punctuation"
        segments = described_class.segment_sentences(text)

        expect(segments.size).to eq(1)
      end
    end
  end
end
