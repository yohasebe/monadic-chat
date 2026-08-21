# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Live Conversation — the dedicated speech-to-speech app family.
#
# What matters here is the app-separation contract: this app pins its model
# list to realtime STS models and declares the speech_to_speech flag the
# frontend keys its entire UI mode on. The mirror-image invariant (ordinary
# apps never offer STS models) lives in computed_model_lists_spec.rb.
LIVE_CONVERSATION_VARIANTS = {
  'LiveConversationOpenAI' => { file: 'live_conversation_openai.mdsl',
                                models: ['gpt-realtime-2.1'] },
  'LiveConversationGrok' => { file: 'live_conversation_grok.mdsl',
                              models: ['grok-voice-think-fast-2.0'] },
  'LiveConversationGemini' => { file: 'live_conversation_gemini.mdsl',
                                models: ['gemini-3.1-flash-live-preview'] }
}.freeze

RSpec.describe 'Live Conversation app definitions' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    dir = File.expand_path('../../../apps/live_conversation', __dir__)
    Dir[File.join(dir, '*.rb')].each { |f| require f }
    LIVE_CONVERSATION_VARIANTS.each_value do |v|
      MonadicDSL::Loader.load(File.join(dir, v[:file]))
    end
  end

  LIVE_CONVERSATION_VARIANTS.each do |klass, expected|
    context klass do
      let(:settings) { Object.const_get(klass).instance_variable_get(:@settings) }

      it 'evaluates the MDSL without error' do
        expect(Object.const_defined?(klass)).to be true
      end

      it 'pins the model list to realtime STS models only' do
        expect(settings[:models]).to eq(expected[:models])
        expect(settings[:model]).to eq(expected[:models].first)
      end

      it 'declares the speech_to_speech app flag' do
        expect(settings[:speech_to_speech]).to be true
      end

      it 'every pinned model passes the STS capability gate (SSOT round trip)' do
        expected[:models].each do |m|
          expect(Monadic::Utils::ModelSpec.supports_speech_to_speech?(m)).to be(true),
                                                                             "#{m} missing supports_speech_to_speech in model_spec.js"
        end
      end
    end
  end
end

RSpec.describe 'LiveConversationOpenAI app definition' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    path = File.expand_path('../../../apps/live_conversation/live_conversation_openai.mdsl', __dir__)
    Dir[File.join(File.dirname(path), '*.rb')].each { |f| require f }
    MonadicDSL::Loader.load(path)
  end

  let(:settings) { Object.const_get('LiveConversationOpenAI').instance_variable_get(:@settings) }

  it 'declares the speech_to_speech app flag the frontend keys the UI mode on' do
    expect(settings[:speech_to_speech]).to be true
  end


  it 'honors initiate_from_assistant as the greeting toggle' do
    expect(settings[:initiate_from_assistant]).to be true
  end

  # The loader auto-injects shared file_operations tools (read/write/list on
  # the shared folder) into every app, so settings[:tools] is NOT empty here
  # even with library_search disabled — and that is fine: the enforceable
  # invariant is wire-level. The STS session config never includes a tools
  # key (pinned in sts_stream_handler_spec), so nothing injected can ever
  # reach the realtime session.
  it 'declares no tools of its own in the MDSL' do
    mdsl = File.read(File.expand_path('../../../apps/live_conversation/live_conversation_openai.mdsl', __dir__))
    expect(mdsl).not_to include('define_tool')
    expect(mdsl).not_to include('import_shared_tools')
    expect(mdsl).not_to include('websearch true')
  end

  it 'does not declare privacy (raw audio goes to the provider; stated in the description)' do
    expect(settings[:privacy]).to be_nil
  end

  it 'does not enable text-oriented display features (math / mermaid / abc)' do
    expect(settings[:math]).to be_nil
    expect(settings[:mermaid]).to be_nil
    expect(settings[:abc]).to be_nil
  end
end
