# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'
require_relative '../../../lib/monadic/utils/model_spec'

# Apps that build their model dropdown by calling ModelSpec at load time
# instead of hardcoding a list.
#
# Two things are pinned here. First, that the MDSL files actually evaluate:
# the expression runs inside the DSL's eval context, so a constant that is not
# loaded there would break app loading at startup rather than at test time.
# Second, that the lists track providerDefaults — the hardcoded versions these
# replaced had gone stale by a whole model generation without anyone noticing,
# which is the failure this arrangement exists to prevent.
RSpec.describe 'MDSL apps computing model lists from providerDefaults' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  let(:openai_chat_models) { Monadic::Utils::ModelSpec.get_provider_models('openai', 'chat') }

  def load_app(rel_path)
    path = File.expand_path("../../../apps/#{rel_path}", __dir__)
    Dir[File.join(File.dirname(path), '*.rb')].each { |f| require f }
    MonadicDSL::Loader.load(path)
  end

  # The generated class carries its settings as a class-level ivar; reading it
  # avoids instantiating the app (which pulls in helper modules and CONFIG).
  def settings_for(const_name)
    Object.const_get(const_name).instance_variable_get(:@settings)
  end

  {
    'LanguagePracticeOpenAI' => 'language_practice/language_practice_openai.mdsl',
    'VoiceInterpreterOpenAI' => 'voice_interpreter/voice_interpreter_openai.mdsl',
    'WebInsightOpenAI' => 'web_insight/web_insight_openai.mdsl'
  }.each do |const_name, rel_path|
    context const_name do
      before { load_app(rel_path) }

      it 'evaluates the MDSL without error' do
        expect(Object.const_defined?(const_name)).to be true
      end

      it 'offers exactly the provider default chat models' do
        expect(settings_for(const_name)[:models]).to eq(openai_chat_models)
      end

      it 'defaults to the first provider default' do
        expect(settings_for(const_name)[:model]).to eq(openai_chat_models.first)
      end
    end
  end

  context 'VoiceChatOpenAI' do
    before { load_app('voice_chat/voice_chat_openai.mdsl') }

    let(:settings) { settings_for('VoiceChatOpenAI') }

    it 'evaluates the MDSL without error' do
      expect(Object.const_defined?('VoiceChatOpenAI')).to be true
    end

    it 'offers the provider defaults plus the speech-to-speech model' do
      expect(settings[:models]).to eq(openai_chat_models + ['gpt-realtime-2.1'])
    end

    # STS is opt-in: it must be reachable from the dropdown but never the
    # model a user lands on by simply opening Voice Chat, since it routes
    # audio through a different (and far more expensive) pipeline.
    it 'does not default to the speech-to-speech model' do
      expect(settings[:model]).to eq(openai_chat_models.first)
      expect(settings[:model]).not_to eq('gpt-realtime-2.1')
    end

    it 'keeps the speech-to-speech model selectable' do
      expect(settings[:models]).to include('gpt-realtime-2.1')
    end
  end

  # The point of computing the list is that a new provider default reaches
  # these apps without anyone editing them.
  it 'tracks providerDefaults rather than a copy of it' do
    load_app('web_insight/web_insight_openai.mdsl')
    expect(settings_for('WebInsightOpenAI')[:models]).not_to be_empty
    expect(openai_chat_models).to include(settings_for('WebInsightOpenAI')[:models].first)
  end
end
