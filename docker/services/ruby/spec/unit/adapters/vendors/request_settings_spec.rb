# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/grok_helper'
require_relative '../../../../lib/monadic/adapters/vendors/ollama_helper'

# Settings the user chose on the page reach the chat request.
RSpec.describe 'chat request settings' do
  describe 'the reasoning effort of a Grok model' do
    subject(:helper) { Class.new { include GrokHelper }.new }

    before do
      allow(Monadic::Utils::ModelSpec).to receive(:get_reasoning_effort_options)
        .and_return({ options: %w[low medium high], default: 'low' })
    end

    it 'is the one the user chose, when the model takes it' do
      expect(helper.send(:grok_reasoning_effort, 'm', 'high')).to eq('high')
      expect(helper.send(:grok_reasoning_effort, 'm', ' medium ')).to eq('medium')
    end

    it 'is not sent for a value the model does not take, or for none' do
      expect(helper.send(:grok_reasoning_effort, 'm', 'xhigh')).to be_nil
      expect(helper.send(:grok_reasoning_effort, 'm', nil)).to be_nil
      expect(helper.send(:grok_reasoning_effort, 'm', '')).to be_nil
    end

    it 'is not sent to a model the catalog gives no efforts' do
      allow(Monadic::Utils::ModelSpec).to receive(:get_reasoning_effort_options).and_return(nil)
      expect(helper.send(:grok_reasoning_effort, 'm', 'high')).to be_nil
    end

    it 'goes into the chat request beside the include for reasoning' do
      source = File.read(File.expand_path('../../../../lib/monadic/adapters/vendors/grok_helper.rb', __dir__))
      expect(source).to match(/body\["include"\] = \["reasoning\.encrypted_content"\]\n(\s*#.*\n)*\s*effort = grok_reasoning_effort\(model, reasoning_effort\)\n\s*body\["reasoning"\] = \{ "effort" => effort \} if effort/)
    end
  end

  describe 'the output limit of an Ollama model' do
    subject(:helper) { Class.new { include OllamaHelper }.new }

    def options(given)
      helper.send(:chat_options, Monadic::TurnSettings.of(given))
    end

    it 'is sent as num_predict' do
      expect(options('temperature' => 0.7, 'max_tokens' => '512')).to eq('temperature' => 0.7, 'num_predict' => 512)
      expect(options('temperature' => 0.2, 'max_tokens' => 32_768)).to include('num_predict' => 32_768)
    end

    it 'is not sent when there is none' do
      [{}, { 'max_tokens' => nil }, { 'max_tokens' => 0 }, { 'max_tokens' => '' }].each do |given|
        expect(options(given.merge('temperature' => '0.7'))).to eq('temperature' => 0.7)
      end
    end
  end
end
