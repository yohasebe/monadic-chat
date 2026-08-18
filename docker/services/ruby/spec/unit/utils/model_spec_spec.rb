require_relative '../../../lib/monadic/utils/model_spec'

RSpec.describe Monadic::Utils::ModelSpec do
  before(:each) do
    described_class.reload!
  end

  describe '.deprecated?' do
    it 'returns true for deprecated models' do
      expect(described_class.deprecated?('gpt-4o')).to be true
      expect(described_class.deprecated?('gpt-4o-mini')).to be true
      expect(described_class.deprecated?('gemini-2.5-flash')).to be true
      expect(described_class.deprecated?('gemini-2.5-pro')).to be true
    end

    it 'returns false for non-deprecated models' do
      expect(described_class.deprecated?('gpt-5.4')).to be false
      expect(described_class.deprecated?('claude-sonnet-4-6')).to be false
      expect(described_class.deprecated?('gemini-3.6-flash')).to be false
      expect(described_class.deprecated?('grok-4-0709')).to be false
    end

    it 'returns false for unknown models' do
      expect(described_class.deprecated?('nonexistent-model')).to be false
    end
  end

  describe '.supports_speech_to_speech?' do
    it 'returns true for STS realtime models' do
      expect(described_class.supports_speech_to_speech?('gpt-realtime-2.1')).to be true
    end

    it 'returns false for normal chat models' do
      expect(described_class.supports_speech_to_speech?('gpt-5')).to be false
    end

    it 'returns false for unknown models' do
      expect(described_class.supports_speech_to_speech?('nonexistent-model')).to be false
    end
  end

  # The Ruby side must agree with model_spec.js on the xAI defaults; the two
  # stacks read the same file, so a drift here means the accessor broke.
  describe 'xAI provider defaults' do
    it 'resolves grok-4.6 as the chat and vision default' do
      expect(described_class.get_provider_default('xai', 'chat')).to eq('grok-4.6')
      expect(described_class.default_vision_model('xai')).to eq('grok-4.6')
    end

    it 'exposes the selectable image models with the cheapest as default' do
      models = described_class.get_provider_models('xai', 'image')
      expect(models.first).to eq('grok-imagine-image')
      expect(models).to include('grok-imagine-image-2.0', 'grok-imagine-image-quality')
      expect(described_class.default_image_model('xai')).to eq('grok-imagine-image')
    end

    it 'catalogs grok-4.6 as vision-capable' do
      expect(described_class.get_model_property('grok-4.6', 'vision_capability')).to be true
    end
  end
end
