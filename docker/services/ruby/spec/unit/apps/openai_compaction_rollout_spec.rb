# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Integration check for the Phase 3 OpenAI Responses API server-side
# compaction rollout. Each listed app should load cleanly with its compaction
# settings carried through to the generated class so that openai_helper can
# attach `context_management: [{ type: "compaction", compact_threshold: N }]`
# to /v1/responses requests.
RSpec.describe 'OpenAI Compaction rollout — integration' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  shared_examples 'compaction-enabled openai app' do |mdsl_rel_path, const_name, expected_threshold|
    let(:mdsl_path) { File.expand_path("../../../apps/#{mdsl_rel_path}", __dir__) }

    before do
      # Load sibling Ruby helpers (e.g. *_constants.rb, *_tools.rb) that define
      # the module constants referenced by the MDSL file.
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

  describe 'Research Assistant OpenAI' do
    include_examples 'compaction-enabled openai app',
                     'research_assistant/research_assistant_openai.mdsl',
                     'ResearchAssistantOpenAI',
                     120_000
  end

  describe 'Code Interpreter OpenAI' do
    include_examples 'compaction-enabled openai app',
                     'code_interpreter/code_interpreter_openai.mdsl',
                     'CodeInterpreterOpenAI',
                     150_000
  end

  describe 'Jupyter Notebook OpenAI' do
    include_examples 'compaction-enabled openai app',
                     'jupyter_notebook/jupyter_notebook_openai.mdsl',
                     'JupyterNotebookOpenAI',
                     150_000
  end
end
