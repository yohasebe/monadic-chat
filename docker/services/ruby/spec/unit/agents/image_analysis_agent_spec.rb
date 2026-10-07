# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/image_analysis_agent'

RSpec.describe ImageAnalysisAgent do
  let(:test_class) do
    Class.new do
      include ImageAnalysisAgent

      attr_accessor :settings

      def initialize
        @settings = { "provider" => "openai" }
      end
    end
  end

  let(:agent) { test_class.new }

  before do
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test-openai-key",
      "ANTHROPIC_API_KEY" => "test-claude-key",
      "GEMINI_API_KEY" => "test-gemini-key",
      "XAI_API_KEY" => "test-grok-key",
      "EXTRA_LOGGING" => nil
    })
    stub_const("SHARED_VOL", "/monadic/data")
    stub_const("LOCAL_SHARED_VOL", File.expand_path(File.join(Dir.home, "monadic", "data")))
  end

  describe '#image_analysis_agent' do
    context 'with valid image' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/image.png").and_return(true)
        allow(File).to receive(:size).with("/test/image.png").and_return(1024)
        allow(File).to receive(:extname).with("/test/image.png").and_return(".png")
        allow(File).to receive(:binread).with("/test/image.png").and_return("PNG_DATA")
        allow(agent).to receive(:vision_query_openai).and_return("A cat sitting on a table")
      end

      it 'returns image description' do
        result = agent.image_analysis_agent(message: "What is this?", image_path: "/test/image.png")
        expect(result).to eq("A cat sitting on a table")
      end

      it 'calls the correct provider method' do
        agent.image_analysis_agent(message: "Describe", image_path: "/test/image.png")
        expect(agent).to have_received(:vision_query_openai)
      end
    end

    context 'with missing image' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/nonexistent.png").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/nonexistent.png").and_return(false)
        local_path = File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "nonexistent.png")
        allow(File).to receive(:exist?).with(local_path).and_return(false)
      end

      it 'returns error for missing file' do
        result = agent.image_analysis_agent(message: "Test", image_path: "/nonexistent.png")
        expect(result).to include("ERROR:")
        expect(result).to include("not found")
      end
    end

    context 'with oversized image' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/huge.png").and_return(true)
        allow(File).to receive(:size).with("/test/huge.png").and_return(15 * 1024 * 1024)
      end

      it 'returns error for files exceeding 10MB' do
        result = agent.image_analysis_agent(message: "Test", image_path: "/test/huge.png")
        expect(result).to include("ERROR:")
        expect(result).to include("too large")
      end
    end

    context 'with unsupported format' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/file.bmp").and_return(true)
        allow(File).to receive(:size).with("/test/file.bmp").and_return(1024)
        allow(File).to receive(:extname).with("/test/file.bmp").and_return(".bmp")
      end

      it 'returns error for unsupported format' do
        result = agent.image_analysis_agent(message: "Test", image_path: "/test/file.bmp")
        expect(result).to include("ERROR:")
        expect(result).to include("Unsupported image format")
      end
    end

    context 'with missing API key' do
      before do
        stub_const("CONFIG", {
          "OPENAI_API_KEY" => "",
          "ANTHROPIC_API_KEY" => "",
          "GEMINI_API_KEY" => "",
          "XAI_API_KEY" => "",
          "EXTRA_LOGGING" => nil
        })
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/image.png").and_return(true)
        allow(File).to receive(:size).with("/test/image.png").and_return(1024)
        allow(File).to receive(:extname).with("/test/image.png").and_return(".png")
        allow(File).to receive(:binread).with("/test/image.png").and_return("PNG_DATA")
      end

      it 'returns error when no API key is available' do
        result = agent.image_analysis_agent(message: "Test", image_path: "/test/image.png")
        expect(result).to include("ERROR:")
        expect(result).to include("needs OPENAI_API_KEY")
      end
    end
  end

  describe '#prepare_image_for_analysis' do
    context 'path traversal prevention' do
      it 'rejects paths with ../ at the start' do
        result = agent.send(:prepare_image_for_analysis, "../etc/passwd")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'rejects paths with /../ in the middle' do
        result = agent.send(:prepare_image_for_analysis, "/monadic/data/../etc/passwd")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'rejects standalone ..' do
        result = agent.send(:prepare_image_for_analysis, "..")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'allows filenames containing double dots' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("report..final.png").and_return(true)
        allow(File).to receive(:size).with("report..final.png").and_return(1024)
        allow(File).to receive(:extname).with("report..final.png").and_return(".png")
        allow(File).to receive(:binread).with("report..final.png").and_return("PNG_DATA")

        result = agent.send(:prepare_image_for_analysis, "report..final.png")
        expect(result).to be_a(Hash)
        expect(result[:base64]).not_to be_nil
      end
    end

    context 'MIME type detection' do
      before do
        allow(File).to receive(:exist?).and_call_original
      end

      %w[jpg jpeg png gif webp].each do |ext|
        it "accepts .#{ext} format" do
          path = "/test/image.#{ext}"
          allow(File).to receive(:exist?).with(path).and_return(true)
          allow(File).to receive(:size).with(path).and_return(1024)
          allow(File).to receive(:extname).with(path).and_return(".#{ext}")
          allow(File).to receive(:binread).with(path).and_return("IMAGE_DATA")

          result = agent.send(:prepare_image_for_analysis, path)
          expect(result).to be_a(Hash)
          expect(result[:mime_type]).to start_with("image/")
        end
      end
    end
  end

  describe '#resolve_vision_provider' do
    it 'returns current provider when it supports vision' do
      agent.settings["provider"] = "anthropic"
      expect(agent.send(:resolve_vision_provider)).to eq("anthropic")
    end

    it 'normalizes Claude alias' do
      agent.settings["provider"] = "claude"
      expect(agent.send(:resolve_vision_provider)).to eq("anthropic")
    end

    it 'normalizes Gemini alias' do
      agent.settings["provider"] = "gemini"
      expect(agent.send(:resolve_vision_provider)).to eq("google")
    end

    # Provider Independence: the image goes to the app's own provider or
    # nowhere, even when another provider has a key.
    it 'does not fall back to another provider for a provider without vision' do
      agent.settings["provider"] = "ollama"
      expect(agent.send(:resolve_vision_provider)).to be_nil
    end

    it 'does not fall back when the current provider has no API key' do
      agent.settings["provider"] = "xai"
      stub_const("CONFIG", {
        "OPENAI_API_KEY" => "test-key",
        "XAI_API_KEY" => "",
        "EXTRA_LOGGING" => nil
      })
      expect(agent.send(:resolve_vision_provider)).to be_nil
      result = agent.image_analysis_agent(message: "Test", image_path: "/test/image.png")
      expect(result).to start_with("ERROR:").and include("XAI_API_KEY")
    end
  end

  # Mistral, Cohere and DeepSeek analyze images with their own models
  # (checked against the live APIs 2026-10-07); nothing goes to another provider.
  describe 'Mistral, Cohere and DeepSeek vision' do
    let(:image) { { base64: "QUJD", mime_type: "image/png" } }
    let(:posted) { [] }

    def ok(body)
      double("res", status: double(success?: true, to_s: "200"), body: body.to_json)
    end

    it 'sends an OpenAI-style image part to Mistral and keeps only the text of the answer' do
      allow(agent).to receive(:vision_http_post) { |uri, _h, body| posted << [uri, body]; ok(choices: [{ message: { content: [{ type: "thinking", thinking: [] }, { type: "text", text: "A menu." }] } }]) }
      result = agent.send(:vision_query_mistral, "What is it?", image, "mistral-small-2603", "k")
      expect(result).to eq("A menu.")
      uri, body = posted.last
      expect(uri).to eq("https://api.mistral.ai/v1/chat/completions")
      expect(body[:messages][0][:content][1]).to eq(type: "image_url", image_url: { url: "data:image/png;base64,QUJD" })
    end

    it 'sends the image to DeepSeek the same way' do
      allow(agent).to receive(:vision_http_post) { |uri, _h, body| posted << [uri, body]; ok(choices: [{ message: { content: "A chart." } }]) }
      expect(agent.send(:vision_query_deepseek, "q", image, "deepseek-v4-flash-vision-exp", "k")).to eq("A chart.")
      expect(posted.last[0]).to eq("https://api.deepseek.com/chat/completions")
    end

    it 'uses the Cohere image part and reads the text parts of the reply' do
      allow(agent).to receive(:vision_http_post) { |uri, _h, body| posted << [uri, body]; ok(message: { content: [{ type: "thinking", thinking: "x" }, { type: "text", text: "A phone." }] }) }
      expect(agent.send(:vision_query_cohere, "q", image, "command-a-plus-05-2026", "k")).to eq("A phone.")
      uri, body = posted.last
      expect(uri).to eq("https://api.cohere.ai/v2/chat")
      expect(body[:messages][0][:content][1]).to eq(type: "image", image: "data:image/png;base64,QUJD")
    end

    it 'reports an API error with the provider name' do
      allow(agent).to receive(:vision_http_post).and_return(
        double("res", status: double(success?: false, to_s: "400"), body: { message: "bad image" }.to_json)
      )
      expect(agent.send(:vision_query_mistral, "q", image, "m", "k")).to start_with("ERROR: Mistral Vision API error (400): bad image")
    end

    it 'routes a Mistral app to Mistral even when OpenAI has a key' do
      agent.settings["provider"] = "mistral"
      stub_const("CONFIG", { "OPENAI_API_KEY" => "o", "MISTRAL_API_KEY" => "m", "EXTRA_LOGGING" => nil })
      allow(agent).to receive(:prepare_image_for_analysis).and_return(image)
      expect(agent).to receive(:vision_query_mistral).and_return("ok")
      expect(agent).not_to receive(:vision_query_openai)
      expect(agent.image_analysis_agent(message: "q", image_path: "x.png")).to eq("ok")
    end
  end

end
