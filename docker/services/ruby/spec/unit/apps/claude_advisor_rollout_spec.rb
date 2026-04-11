# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Integration check for the Phase 2 Advisor Tool rollout to additional
# Claude apps beyond AutoForge. Each app should load cleanly with
# Sonnet 4.6 as executor and Opus 4.6 as advisor (canonical pairing),
# and carry the advisor_tool settings through to the generated class.
RSpec.describe 'Claude Advisor Tool rollout — integration' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  shared_examples 'advisor-enabled claude app' do |mdsl_rel_path, const_name, expected_max_uses|
    let(:mdsl_path) { File.expand_path("../../../apps/#{mdsl_rel_path}", __dir__) }

    # Force a fresh MDSL load before every example. Using the
    # `unless Object.const_defined?` optimization causes intermittent
    # failures under RSpec random ordering: an earlier example in a
    # sibling describe block may have left the class cached at a state
    # produced by a different MDSL loader pass, and our `unless` guard
    # then skips reloading.
    before do
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

    it 'sets Sonnet 4.6 as the executor (canonical advisor pairing)' do
      expect(settings[:model] || settings['model']).to eq('claude-sonnet-4-6')
    end

    it 'carries advisor_tool settings into the generated class' do
      advisor = settings[:advisor_tool] || settings['advisor_tool']

      expect(advisor).not_to be_nil
      expect(advisor[:model] || advisor['model']).to eq('claude-opus-4-6')
      expect(advisor[:max_uses] || advisor['max_uses']).to eq(expected_max_uses)

      caching = advisor[:caching] || advisor['caching']
      expect(caching).not_to be_nil
      expect(caching[:type] || caching['type']).to eq('ephemeral')
    end
  end

  describe 'Coding Assistant Claude' do
    include_examples 'advisor-enabled claude app',
                     'coding_assistant/coding_assistant_claude.mdsl',
                     'CodingAssistantClaude',
                     2
  end

  describe 'Jupyter Notebook Claude' do
    include_examples 'advisor-enabled claude app',
                     'jupyter_notebook/jupyter_notebook_claude.mdsl',
                     'JupyterNotebookClaude',
                     2
  end
end
