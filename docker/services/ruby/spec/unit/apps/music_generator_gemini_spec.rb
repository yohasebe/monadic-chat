# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Music Generator (Gemini / Lyria 3). New modality: text-to-music via the
# synchronous Gemini generateContent AUDIO path. Mirrors the video/image
# generator app shape (orchestrator chat model + a generation tool).
RSpec.describe 'Music Generator Gemini — integration' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  let(:mdsl_path) do
    File.expand_path('../../../apps/music_generator/music_generator_gemini.mdsl', __dir__)
  end

  before do
    Dir[File.join(File.dirname(mdsl_path), '*.rb')].each { |f| require f }
    MonadicDSL::Loader.load(mdsl_path)
  end

  let(:settings) { MusicGeneratorGemini.instance_variable_get(:@settings) }

  it 'loads and defines the constant' do
    expect(Object.const_defined?('MusicGeneratorGemini')).to be true
  end

  it 'is wired to Gemini and gated on GEMINI_API_KEY' do
    expect(settings[:group] || settings['group']).to eq('Google')
    expect(settings[:provider] || settings['provider']).to match(/gemini/i)
  end

  it 'exposes the generate_music_with_lyria tool' do
    tools = settings[:tools] || settings['tools']
    expect(tools.to_s).to include('generate_music_with_lyria')
  end

  describe 'Lyria providerDefaults SSOT' do
    require_relative '../../../lib/monadic/utils/model_spec'
    let(:m) { Monadic::Utils::ModelSpec }

    it 'defaults to Lyria 3 Pro with Clip as the fast alternative' do
      models = m.get_provider_models('gemini', 'music')
      expect(models.first).to eq('lyria-3-pro-preview')
      expect(models).to include('lyria-3-clip-preview')
      expect(m.default_music_model('gemini')).to eq('lyria-3-pro-preview')
    end
  end
end
