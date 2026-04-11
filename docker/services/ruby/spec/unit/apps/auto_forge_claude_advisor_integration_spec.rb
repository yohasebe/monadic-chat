# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Integration check: verify auto_forge_claude.mdsl loads cleanly with the new
# advisor_tool DSL block and that the generated class carries advisor_tool
# settings through to runtime.
RSpec.describe 'AutoForge Claude advisor_tool integration' do
  let(:mdsl_path) do
    File.expand_path('../../../apps/auto_forge/auto_forge_claude.mdsl', __dir__)
  end

  before(:all) do
    # Ensure APPS constant exists (some loaders expect it)
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  it 'the MDSL file exists' do
    expect(File.exist?(mdsl_path)).to be true
  end

  it 'loads auto_forge_claude.mdsl without errors' do
    expect { MonadicDSL::Loader.load(mdsl_path) }.not_to raise_error
    expect(Object.const_defined?('AutoForgeClaude')).to be true
  end

  it 'carries advisor_tool settings into the generated class @settings' do
    MonadicDSL::Loader.load(mdsl_path) unless Object.const_defined?('AutoForgeClaude')
    settings = Object.const_get('AutoForgeClaude').instance_variable_get(:@settings)
    advisor = settings[:advisor_tool] || settings['advisor_tool']

    expect(advisor).not_to be_nil
    expect(advisor[:model] || advisor['model']).to eq('claude-opus-4-6')
    expect(advisor[:max_uses] || advisor['max_uses']).to eq(3)

    caching = advisor[:caching] || advisor['caching']
    expect(caching).not_to be_nil
    expect(caching[:type] || caching['type']).to eq('ephemeral')
  end
end
