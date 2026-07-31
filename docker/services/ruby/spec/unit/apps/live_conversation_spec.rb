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
RSpec.describe 'LiveConversationOpenAI app definition' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    path = File.expand_path('../../../apps/live_conversation/live_conversation_openai.mdsl', __dir__)
    Dir[File.join(File.dirname(path), '*.rb')].each { |f| require f }
    MonadicDSL::Loader.load(path)
  end

  let(:settings) { Object.const_get('LiveConversationOpenAI').instance_variable_get(:@settings) }

  it 'evaluates the MDSL without error' do
    expect(Object.const_defined?('LiveConversationOpenAI')).to be true
  end

  it 'pins the model list to realtime STS models only' do
    expect(settings[:models]).to eq(['gpt-realtime-2.1'])
    expect(settings[:model]).to eq('gpt-realtime-2.1')
  end

  it 'declares the speech_to_speech app flag the frontend keys the UI mode on' do
    expect(settings[:speech_to_speech]).to be true
  end

  it 'honors initiate_from_assistant as the greeting toggle' do
    expect(settings[:initiate_from_assistant]).to be true
  end

  # The loader auto-injects shared tools (e.g. library_search) into every
  # app, so settings[:tools] is NOT empty here — and that is fine: the
  # enforceable invariant is wire-level. The STS session config never
  # includes a tools key (pinned in sts_stream_handler_spec), so nothing
  # injected can ever reach the realtime session.
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
