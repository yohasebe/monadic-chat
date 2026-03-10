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
      expect(described_class.deprecated?('grok-3')).to be true
    end

    it 'returns false for non-deprecated models' do
      expect(described_class.deprecated?('gpt-5.4')).to be false
      expect(described_class.deprecated?('claude-sonnet-4-6')).to be false
      expect(described_class.deprecated?('gemini-3-flash-preview')).to be false
      expect(described_class.deprecated?('grok-4-0709')).to be false
    end

    it 'returns false for unknown models' do
      expect(described_class.deprecated?('nonexistent-model')).to be false
    end
  end
end
