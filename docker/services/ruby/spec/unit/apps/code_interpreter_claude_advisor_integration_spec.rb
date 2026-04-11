# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Integration check: verify code_interpreter_claude.mdsl loads cleanly with
# the advisor_tool DSL block and that the generated class carries the
# Sonnet + Opus advisor pairing through to runtime.
RSpec.describe 'Code Interpreter Claude advisor_tool integration' do
  let(:mdsl_path) do
    File.expand_path('../../../apps/code_interpreter/code_interpreter_claude.mdsl', __dir__)
  end

  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  it 'the MDSL file exists' do
    expect(File.exist?(mdsl_path)).to be true
  end

  it 'loads code_interpreter_claude.mdsl without errors' do
    expect { MonadicDSL::Loader.load(mdsl_path) }.not_to raise_error
    expect(Object.const_defined?('CodeInterpreterClaude')).to be true
  end

  it 'sets Sonnet 4.6 as the executor (canonical advisor pairing)' do
    MonadicDSL::Loader.load(mdsl_path) unless Object.const_defined?('CodeInterpreterClaude')
    settings = Object.const_get('CodeInterpreterClaude').instance_variable_get(:@settings)
    expect(settings[:model] || settings['model']).to eq('claude-sonnet-4-6')
  end

  it 'carries advisor_tool settings into the generated class @settings' do
    MonadicDSL::Loader.load(mdsl_path) unless Object.const_defined?('CodeInterpreterClaude')
    settings = Object.const_get('CodeInterpreterClaude').instance_variable_get(:@settings)
    advisor = settings[:advisor_tool] || settings['advisor_tool']

    expect(advisor).not_to be_nil
    expect(advisor[:model] || advisor['model']).to eq('claude-opus-4-6')
    expect(advisor[:max_uses] || advisor['max_uses']).to eq(2)

    caching = advisor[:caching] || advisor['caching']
    expect(caching).not_to be_nil
    expect(caching[:type] || caching['type']).to eq('ephemeral')
  end

  it 'keeps reasoning_effort at "none" (thinking off, advisor handles deep reasoning)' do
    MonadicDSL::Loader.load(mdsl_path) unless Object.const_defined?('CodeInterpreterClaude')
    settings = Object.const_get('CodeInterpreterClaude').instance_variable_get(:@settings)
    expect(settings[:reasoning_effort] || settings['reasoning_effort']).to eq('none')
  end
end
