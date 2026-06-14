# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# The Cohere coding apps are pointed at North Mini Code with reasoning on.
# Verify the model override and reasoning_effort propagate to the generated
# class so cohere_helper sends the right model and enables thinking.
RSpec.describe 'Cohere North coding rollout — integration' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  shared_examples 'north-backed cohere coding app' do |mdsl_rel_path, const_name|
    let(:mdsl_path) { File.expand_path("../../../apps/#{mdsl_rel_path}", __dir__) }

    before do
      Dir[File.join(File.dirname(mdsl_path), '*.rb')].each { |f| require f }
      MonadicDSL::Loader.load(mdsl_path)
    end

    let(:settings) { Object.const_get(const_name).instance_variable_get(:@settings) }

    it 'loads and defines the constant' do
      expect(Object.const_defined?(const_name)).to be true
    end

    it 'uses North Mini Code as its model' do
      expect(settings[:model] || settings['model']).to eq('north-mini-code-1-0')
    end

    it 'lists North Mini Code first in the curated dropdown' do
      models = settings[:models] || settings['models']
      expect(models).to be_a(Array)
      expect(models.first).to eq('north-mini-code-1-0')
    end

    it 'enables reasoning' do
      expect(settings[:reasoning_effort] || settings['reasoning_effort']).to eq('enabled')
    end
  end

  describe 'Coding Assistant Cohere' do
    include_examples 'north-backed cohere coding app',
                     'coding_assistant/coding_assistant_cohere.mdsl',
                     'CodingAssistantCohere'
  end

  describe 'Code Interpreter Cohere' do
    include_examples 'north-backed cohere coding app',
                     'code_interpreter/code_interpreter_cohere.mdsl',
                     'CodeInterpreterCohere'
  end
end
