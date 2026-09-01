# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/utils/model_spec'
require_relative '../../../lib/monadic/utils/stt_utils'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'

# STT routing is decided by the `stt_provider` declaration in model_spec.js.
# These specs pin the invariants that make that the single source of truth:
# every model offered in the UI resolves, the dispatcher covers every provider
# it can resolve to, and a model is never handed to a provider that does not
# own it.
RSpec.describe 'STT provider routing' do
  MS = Monadic::Utils::ModelSpec

  # The models offered by the Speech-to-Text selector in views/index.erb.
  # Read from the view so the list cannot drift away from what users see.
  def self.dropdown_stt_models
    view = File.expand_path('../../../views/index.erb', __dir__)
    section = File.read(view)[/<select[^>]*id="stt-model".*?<\/select>/m]
    raise 'stt-model select not found in views/index.erb' unless section

    section.scan(/<option[^>]*value="([^"]+)"/).flatten.reject(&:empty?)
  end

  describe 'every model in the Speech-to-Text selector' do
    dropdown_stt_models.each do |model|
      it "#{model} resolves to a provider the dispatcher can serve" do
        provider = MS.stt_provider(model)

        expect(provider).to be_a(String)
        expect(provider).not_to be_empty

        # "openai" is served by the inline path at the end of stt_api_request;
        # everything else must have a request method registered.
        next if provider == 'openai'

        expect(InteractionUtils::STT_PROVIDER_REQUEST_METHODS).to have_key(provider),
          "#{model} declares stt_provider #{provider.inspect}, which no request method serves. " \
          'Add it to InteractionUtils::STT_PROVIDER_REQUEST_METHODS.'
      end
    end
  end

  describe 'the selector never offers a deprecated model' do
    dropdown_stt_models.each do |model|
      it "#{model} is not deprecated" do
        expect(MS.get_model_property(model, 'deprecated')).not_to eq(true),
          "views/index.erb offers #{model}, which model_spec.js marks deprecated. " \
          "Offer its successor instead: #{MS.get_model_property(model, 'successor').inspect}."
      end
    end
  end

  describe 'every request method the dispatcher registers is implemented' do
    InteractionUtils::STT_PROVIDER_REQUEST_METHODS.each do |provider, method_name|
      it "#{provider} -> #{method_name} exists" do
        expect(InteractionUtils.instance_methods).to include(method_name)
      end
    end
  end

  describe 'AudioTranscriptionAgent.model_for' do
    it 'passes the requested model through when the provider owns it' do
      expect(AudioTranscriptionAgent.model_for('google', 'gemini-3.6-flash'))
        .to eq('gemini-3.6-flash')
    end

    it 'ignores a model belonging to another provider' do
      # A Gemini app with an OpenAI STT model selected must not send that
      # model name to the Gemini endpoint.
      expect(AudioTranscriptionAgent.model_for('google', 'whisper-1'))
        .to eq(AudioTranscriptionAgent.audio_model_for('google'))
    end

    it 'ignores a Gemini model when the resolved provider is OpenAI' do
      expect(AudioTranscriptionAgent.model_for('openai', 'gemini-3.6-flash'))
        .to eq(AudioTranscriptionAgent.audio_model_for('openai'))
    end

    it 'falls back to the provider default when nothing is requested' do
      expect(AudioTranscriptionAgent.model_for('openai', nil))
        .to eq(AudioTranscriptionAgent.audio_model_for('openai'))
      expect(AudioTranscriptionAgent.model_for('openai', '  '))
        .to eq(AudioTranscriptionAgent.audio_model_for('openai'))
    end
  end

  describe 'ModelSpec.stt_provider' do
    it 'reads the declaration rather than the model name' do
      expect(MS.stt_provider('scribe_v2')).to eq('elevenlabs')
      expect(MS.stt_provider('xai-stt')).to eq('xai')
    end

    it 'defaults to openai for an undeclared model with no provider-ish name' do
      expect(MS.stt_provider('whisper-1')).to eq('openai')
      expect(MS.stt_provider('a-model-that-does-not-exist')).to eq('openai')
    end

    it 'falls back to the name for an undeclared model' do
      # Variants a user can add via ~/monadic/config/models.json, or a provider
      # revision selected before its catalog entry lands. Routing these to
      # OpenAI would send the model value to the wrong endpoint.
      expect(MS.stt_provider('voxtral-mini-transcribe-26-02')).to eq('mistral')
      expect(MS.stt_provider('xai-stt-1')).to eq('xai')
      expect(MS.stt_provider('scribe_v3')).to eq('elevenlabs')
    end

    it 'lets a declaration override what the name suggests' do
      # A declaration must beat the name, or a model whose siblings use a
      # different API is routed by its prefix to the wrong one.
      expect(MS.stt_provider_from_name('gemini-3.5-transcribe')).to eq('gemini')

      allow(MS).to receive(:get_model_property)
        .with('gemini-3.5-transcribe', 'stt_provider').and_return('gemini_interactions')
      expect(MS.stt_provider('gemini-3.5-transcribe')).to eq('gemini_interactions')
    end
  end
end
