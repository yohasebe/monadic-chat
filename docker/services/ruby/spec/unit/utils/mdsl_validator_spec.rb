# frozen_string_literal: true

require_relative '../../spec_helper'
require 'monadic/utils/mdsl_validator'

# MDSLValidator flags a reasoning setting that the request code would not
# send: a value outside the levels the named model lists in model_spec.js.
# Rules per provider are not repeated in the validator (an earlier version
# had them, and they drifted: it called reasoning_effort wrong for Claude,
# Gemini, Mistral and Cohere, all of which send it). So these specs check the
# rule against the model list, and that no app's MDSL trips it.
RSpec.describe Monadic::Utils::MDSLValidator do
  def validate(config, model, provider = 'Any')
    described_class.validate_reasoning_parameters(config, provider, model)
  end

  it 'accepts a level the model lists, in either shape of list' do
    expect(validate({ reasoning_effort: 'max' }, 'deepseek-v4-pro')).to eq(errors: [], warnings: [])
    expect(validate({ reasoning_content: 'enabled' }, 'deepseek-v4-pro')).to eq(errors: [], warnings: [])
    expect(validate({ reasoning_effort: 'enabled' }, 'north-mini-code-1-0')).to eq(errors: [], warnings: [])
  end

  it 'accepts "none", which every provider sends as its least reasoning' do
    expect(validate({ reasoning_effort: 'none' }, 'gpt-6.1-sol')).to eq(errors: [], warnings: [])
  end

  it 'warns, without an error, about a level the model does not take' do
    result = validate({ reasoning_effort: 'low' }, 'deepseek-v4-flash')
    expect(result[:errors]).to be_empty
    expect(result[:warnings]).to eq(["reasoning_effort 'low' is not a level deepseek-v4-flash takes (high, max); it is not sent"])
    expect(validate({ reasoning_content: 'maybe' }, 'deepseek-v4-pro')[:warnings].first).to include("reasoning_content 'maybe'")
  end

  it 'says nothing when the model lists no levels (its request code decides)' do
    model = Monadic::Utils::ModelSpec.load_spec.keys.find { |m| Monadic::Utils::ModelSpec.get_model_spec(m)['reasoning_effort'].nil? }
    expect(validate({ reasoning_effort: 'high' }, model)).to eq(errors: [], warnings: [])
  end

  it 'reports a model missing from the specification' do
    expect(validate({ reasoning_effort: 'high' }, 'no-such-model')[:errors]).to eq(["Model 'no-such-model' not found in specifications"])
  end

  it "finds nothing to report in any app's MDSL" do
    apps = File.expand_path('../../../apps', __dir__)
    reports = Dir[File.join(apps, '**', '*.mdsl')].sort.filter_map do |file|
      text = File.read(file)
      model = text[/^\s*model\s+\[?\s*"([^"]+)"/, 1]
      config = %w[reasoning_effort reasoning_content].to_h { |k| [k.to_sym, text[/^\s*#{k}\s+"([^"]+)"/, 1]] }.compact
      next unless model && !config.empty?

      result = validate(config, model)
      messages = result[:errors] + result[:warnings]
      "#{File.basename(file)}: #{messages.join('; ')}" unless messages.empty?
    end
    expect(reports).to be_empty
  end
end
