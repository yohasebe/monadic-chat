# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Integration check for the xAI Context Compaction rollout. Each listed Grok
# app should load cleanly with its `compaction` settings carried through to the
# generated class so grok_helper can orchestrate POST /v1/responses/compact and
# rebuild input as [blob, system, tail].
RSpec.describe 'Grok Compaction rollout — integration' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  shared_examples 'compaction-enabled grok app' do |mdsl_rel_path, const_name, expected_threshold|
    let(:mdsl_path) { File.expand_path("../../../apps/#{mdsl_rel_path}", __dir__) }

    before do
      Dir[File.join(File.dirname(mdsl_path), '*.rb')].each { |f| require f }
      MonadicDSL::Loader.load(mdsl_path)
    end

    let(:settings) do
      Object.const_get(const_name).instance_variable_get(:@settings)
    end

    it 'the MDSL file exists' do
      expect(File.exist?(mdsl_path)).to be true
    end

    it 'loads without errors and defines the constant' do
      expect(Object.const_defined?(const_name)).to be true
    end

    it 'carries compaction settings into the generated class' do
      compaction = settings[:compaction] || settings['compaction']
      expect(compaction).not_to be_nil

      threshold = compaction[:compact_threshold] || compaction['compact_threshold']
      expect(threshold).to eq(expected_threshold)
    end
  end

  describe 'Code Interpreter Grok' do
    include_examples 'compaction-enabled grok app',
                     'code_interpreter/code_interpreter_grok.mdsl',
                     'CodeInterpreterGrok',
                     150_000
  end

  describe 'Coding Assistant Grok' do
    include_examples 'compaction-enabled grok app',
                     'coding_assistant/coding_assistant_grok.mdsl',
                     'CodingAssistantGrok',
                     150_000
  end

  describe 'Jupyter Notebook Grok' do
    include_examples 'compaction-enabled grok app',
                     'jupyter_notebook/jupyter_notebook_grok.mdsl',
                     'JupyterNotebookGrok',
                     150_000
  end

  describe 'Auto Forge Grok' do
    include_examples 'compaction-enabled grok app',
                     'auto_forge/auto_forge_grok.mdsl',
                     'AutoForgeGrok',
                     180_000
  end
end
