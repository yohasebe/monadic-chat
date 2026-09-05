# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/utils/model_spec'
require_relative '../../../lib/monadic/utils/stt_utils'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'

# A Speech-to-Text selection is saved for 30 days and reaches the server as a
# plain string. When the catalog retires the model behind that string, the
# frontend migrates its own saved value on load, but the same string also
# arrives by paths that never run that code — a session parameter another
# component reads, a client that does not use the dropdown. Without a
# server-side resolution the request goes out under a name the provider has
# dropped, and the user sees the provider's error rather than a working
# transcript.
#
# This matters on a schedule: OpenAI retires four transcription models on
# 2027-02-26, and gpt-4o-transcribe-diarize stays in the catalog past that date
# because speaker diarization has no successor yet.
RSpec.describe 'Deprecated model resolution' do
  MS = Monadic::Utils::ModelSpec

  describe 'ModelSpec.resolve_deprecated_model' do
    it 'follows a deprecated model to its successor' do
      expect(MS.get_model_property('whisper-1', 'deprecated')).to be(true),
        'whisper-1 is no longer marked deprecated; pick another retired model for this example'

      expect(MS.resolve_deprecated_model('whisper-1')).to eq('gpt-transcribe')
    end

    it 'leaves a current model untouched' do
      expect(MS.resolve_deprecated_model('gpt-transcribe')).to eq('gpt-transcribe')
    end

    it 'leaves a model it does not know untouched' do
      expect(MS.resolve_deprecated_model('a-model-that-was-removed'))
        .to eq('a-model-that-was-removed')
    end

    it 'keeps a deprecated model that names no successor' do
      allow(MS).to receive(:get_model_property).and_call_original
      allow(MS).to receive(:get_model_property).with('orphan', 'deprecated').and_return(true)
      allow(MS).to receive(:get_model_property).with('orphan', 'successor').and_return(nil)

      expect(MS.resolve_deprecated_model('orphan')).to eq('orphan')
    end

    it 'stops instead of looping when successors point at each other' do
      allow(MS).to receive(:get_model_property).and_call_original
      { 'a' => 'b', 'b' => 'a' }.each do |from, to|
        allow(MS).to receive(:get_model_property).with(from, 'deprecated').and_return(true)
        allow(MS).to receive(:get_model_property).with(from, 'successor').and_return(to)
      end

      expect { Timeout.timeout(2) { MS.resolve_deprecated_model('a') } }.not_to raise_error
    end
  end

  describe 'every entry point resolves before the request is built' do
    # The three places a saved selection reaches the server.
    it 'the batch dispatcher routes a retired model by its successor' do
      # whisper-1 and its successor are both OpenAI, so the observable effect
      # is the provider the dispatcher picks for the resolved name.
      resolved = MS.resolve_deprecated_model('whisper-1')

      expect(resolved).not_to eq('whisper-1')
      expect(MS.stt_provider(resolved)).to eq('openai')
    end

    it 'the transcription agent passes the successor through' do
      expect(AudioTranscriptionAgent.model_for('openai', 'whisper-1'))
        .to eq('gpt-transcribe')
    end

    it 'a retired Gemini selection still resolves within its own provider' do
      # gemini-2.5-flash was dropped from the selector; its successor must stay
      # on the Gemini side rather than falling back to the OpenAI default.
      resolved = MS.resolve_deprecated_model('gemini-2.5-flash')

      expect(resolved).to eq('gemini-3.6-flash')
      expect(MS.stt_provider(resolved)).to eq('gemini')
      expect(AudioTranscriptionAgent.model_for('google', 'gemini-2.5-flash'))
        .to eq('gemini-3.6-flash')
    end
  end

  describe 'the catalog keeps retired models resolvable' do
    it 'gives every deprecated STT model a successor that is not itself deprecated' do
      stt_models = MS.load_spec.select do |_model, props|
        props.is_a?(Hash) && props['deprecated'] == true &&
          (props.key?('stt_provider') || props['stt_capability'] == true)
      end

      expect(stt_models).not_to be_empty,
        'no deprecated STT models in the catalog; this example checks nothing'

      stt_models.each_key do |model|
        resolved = MS.resolve_deprecated_model(model)

        expect(resolved).not_to eq(model),
          "#{model} is deprecated but names no successor, so a saved selection stays broken"
        expect(MS.get_model_property(resolved, 'deprecated')).not_to eq(true),
          "#{model} resolves to #{resolved}, which is itself deprecated"
      end
    end
  end
end
