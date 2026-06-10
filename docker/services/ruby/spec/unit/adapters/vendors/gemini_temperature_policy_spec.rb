# frozen_string_literal: true

require 'spec_helper'

# Gemini temperature policy.
#
# The Gemini 3 Developer Guide strongly recommends keeping temperature at its
# default (1.0) for ALL Gemini 3 models — lower values risk looping or degraded
# output — and advises removing explicitly set low temperatures. The SSOT for
# "this model accepts a user temperature" is the `temperature` key in
# model_spec.js (it also drives the Web UI slider); no Gemini entry carries it,
# yet MDSL-set temperatures were reaching the API. These examples pin the
# accessor semantics, the helper gate, and the MDSL cleanup.
RSpec.describe 'Gemini temperature policy' do
  describe 'ModelSpec.supports_temperature?' do
    it 'is false for Gemini models (no temperature key in the spec)' do
      expect(Monadic::Utils::ModelSpec.supports_temperature?("gemini-3.5-flash")).to be false
      expect(Monadic::Utils::ModelSpec.supports_temperature?("gemini-3.1-pro-preview")).to be false
      expect(Monadic::Utils::ModelSpec.supports_temperature?("gemini-2.5-flash")).to be false
    end

    it 'is true for models whose spec advertises a temperature range' do
      expect(Monadic::Utils::ModelSpec.supports_temperature?("deepseek-v4-pro")).to be true
    end
  end

  describe 'GeminiHelper request-body gate' do
    let(:helper) do
      Class.new { include GeminiHelper }.new
    end

    def build_body(temperature:, model_name: "gemini-3.5-flash")
      helper.send(:build_gemini_request_body,
                  obj: { "model" => model_name },
                  model_name: model_name,
                  session: { parameters: {} },
                  context: [],
                  temperature: temperature,
                  max_tokens: 1000,
                  is_thinking_model: false,
                  thinking_level: nil,
                  reasoning_effort: nil,
                  tool_capable: false,
                  system_message: nil)
    end

    it 'drops an MDSL/user temperature for models without spec support' do
      body = build_body(temperature: 0.5)
      expect(body.dig("generationConfig", "temperature")).to be_nil
    end

    it 'passes temperature through when the spec supports it' do
      allow(Monadic::Utils::ModelSpec).to receive(:supports_temperature?).and_return(true)
      body = build_body(temperature: 0.5)
      expect(body.dig("generationConfig", "temperature")).to eq(0.5)
    end
  end

  describe 'Gemini MDSL files' do
    it 'set no temperature (dead config for Gemini 3; the helper drops it anyway)' do
      apps_root = File.expand_path('../../../../apps', __dir__)
      offenders = Dir.glob(File.join(apps_root, '*/*.mdsl')).select do |f|
        src = File.read(f)
        src.include?('provider "gemini"') && src.match?(/^\s*temperature [0-9.]+\s*$/)
      end
      expect(offenders).to be_empty, "Gemini MDSL files set temperature: #{offenders.map { |f| File.basename(f) }.join(', ')}"
    end
  end
end
