require_relative '../../../lib/monadic/utils/model_spec'

RSpec.describe Monadic::Utils::ModelSpec, 'provider defaults' do
  before(:each) do
    described_class.reload!
  end

  describe '.load_provider_defaults' do
    it 'returns a Hash' do
      result = described_class.load_provider_defaults
      expect(result).to be_a(Hash)
    end

    it 'contains all expected providers' do
      result = described_class.load_provider_defaults
      %w[openai anthropic gemini cohere mistral xai perplexity deepseek ollama].each do |provider|
        expect(result).to have_key(provider), "Expected providerDefaults to include #{provider}"
      end
    end

    it 'caches the result' do
      first = described_class.load_provider_defaults
      second = described_class.load_provider_defaults
      expect(first).to equal(second)
    end
  end

  describe '.get_provider_default' do
    it 'returns the first model for openai chat' do
      expect(described_class.get_provider_default("openai", "chat")).to eq("gpt-5.4")
    end

    it 'returns the first model for anthropic chat' do
      expect(described_class.get_provider_default("anthropic", "chat")).to eq("claude-sonnet-4-6")
    end

    it 'returns the first model for gemini chat' do
      expect(described_class.get_provider_default("gemini", "chat")).to eq("gemini-3-flash-preview")
    end

    it 'returns the first model for xai code' do
      expect(described_class.get_provider_default("xai", "code")).to eq("grok-code-fast-1")
    end

    it 'returns nil for non-existent provider' do
      expect(described_class.get_provider_default("nonexistent")).to be_nil
    end

    it 'returns nil for non-existent category' do
      expect(described_class.get_provider_default("cohere", "vision")).to be_nil
    end

    it 'defaults to chat category when category is omitted' do
      expect(described_class.get_provider_default("openai")).to eq("gpt-5.4")
    end
  end

  describe '.get_provider_models' do
    it 'returns the full model list for openai chat' do
      models = described_class.get_provider_models("openai", "chat")
      expect(models).to be_an(Array)
      expect(models.length).to be >= 2
      expect(models.first).to eq("gpt-5.4")
    end

    it 'returns the full model list for openai code' do
      models = described_class.get_provider_models("openai", "code")
      expect(models).to include("gpt-5.3-codex")
    end

    it 'returns nil for non-existent provider' do
      expect(described_class.get_provider_models("nonexistent")).to be_nil
    end
  end

  describe 'provider key normalization' do
    it 'normalizes "google" to "gemini"' do
      expect(described_class.get_provider_default("google", "chat")).to eq(
        described_class.get_provider_default("gemini", "chat")
      )
    end

    it 'normalizes "claude" to "anthropic"' do
      expect(described_class.get_provider_default("claude", "chat")).to eq(
        described_class.get_provider_default("anthropic", "chat")
      )
    end

    it 'normalizes "grok" to "xai"' do
      expect(described_class.get_provider_default("grok", "chat")).to eq(
        described_class.get_provider_default("xai", "chat")
      )
    end

    it 'handles uppercase provider names' do
      expect(described_class.get_provider_default("OpenAI", "chat")).to eq("gpt-5.4")
    end

    it 'handles provider names with surrounding whitespace' do
      expect(described_class.get_provider_default("  openai  ", "chat")).to eq("gpt-5.4")
    end

    it 'handles provider alias with whitespace' do
      expect(described_class.get_provider_default(" Google ", "chat")).to eq(
        described_class.get_provider_default("gemini", "chat")
      )
    end
  end

  describe 'convenience accessors' do
    it '.default_chat_model returns the chat default' do
      expect(described_class.default_chat_model("openai")).to eq("gpt-5.4")
    end

    it '.default_code_model returns the code default' do
      expect(described_class.default_code_model("openai")).to eq("gpt-5.3-codex")
    end

    it '.default_vision_model returns the vision default' do
      expect(described_class.default_vision_model("openai")).to eq("gpt-4.1-mini")
    end

    it '.default_audio_model returns the audio_transcription default' do
      expect(described_class.default_audio_model("openai")).to eq("gpt-4o-mini-transcribe-2025-12-15")
    end

    it '.default_image_model returns the image default' do
      expect(described_class.default_image_model("openai")).to eq("gpt-image-2")
    end

    it '.default_video_model returns nil when OpenAI video category removed (Sora API shutdown)' do
      expect(described_class.default_video_model("openai")).to be_nil
    end

    it '.default_tts_model returns the tts default' do
      expect(described_class.default_tts_model("openai")).to eq("gpt-4o-mini-tts-2025-12-15")
    end

    it '.default_image_model returns nil when category does not exist' do
      expect(described_class.default_image_model("cohere")).to be_nil
    end

    it '.default_video_model for gemini returns veo model' do
      expect(described_class.default_video_model("gemini")).to eq("veo-3.1-fast-generate-preview")
    end

    it '.default_image_model for xai returns grok-imagine-image' do
      expect(described_class.default_image_model("xai")).to eq("grok-imagine-image")
    end

    it '.default_code_model returns nil when category does not exist' do
      expect(described_class.default_code_model("cohere")).to be_nil
    end

    it '.default_embedding_model returns the embedding default' do
      expect(described_class.default_embedding_model("openai")).to eq("text-embedding-3-large")
    end

    it '.default_embedding_model returns nil for providers without embedding' do
      expect(described_class.default_embedding_model("anthropic")).to be_nil
    end
  end

  describe '.reload!' do
    it 'clears both spec and provider_defaults caches' do
      # Load both caches
      described_class.load_spec
      described_class.load_provider_defaults

      # Reload should clear both and reload spec
      described_class.reload!

      # Should still work after reload
      expect(described_class.get_provider_default("openai")).to eq("gpt-5.4")
    end

    it 'clears JS file content cache so file changes are picked up' do
      # Load to populate cache
      described_class.load_provider_defaults

      # Reload should clear @js_content
      described_class.reload!

      # After reload, provider defaults should still load correctly
      result = described_class.load_provider_defaults
      expect(result).to have_key("openai")
    end
  end

  describe 'error handling' do
    it 'load_provider_defaults returns empty hash when JS parsing fails' do
      # Force a reload so next call reads fresh
      described_class.reload!

      # Stub read_model_spec_js to return invalid content
      allow(described_class).to receive(:read_model_spec_js).and_return("const providerDefaults = { INVALID JSON }")

      result = described_class.load_provider_defaults
      expect(result).to eq({})
    end

    it 'load_provider_defaults returns empty hash when file is missing' do
      described_class.reload!
      allow(described_class).to receive(:read_model_spec_js).and_return(nil)

      result = described_class.load_provider_defaults
      expect(result).to eq({})
    end
  end
end
