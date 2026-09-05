# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/model_spec'

# GPT-6 Astra restricts four things the OpenAI helper would otherwise send.
# All four were verified against the live API on 2026-09-05; each is handled by
# a declaration in model_spec.js rather than a branch in the helper, so these
# examples pin the declarations.
RSpec.describe 'GPT-6 Astra request contract' do
  MS = Monadic::Utils::ModelSpec
  ASTRA = 'gpt-6-astra'

  describe 'reasoning effort' do
    # Live: "none" and "minimal" return 400 unsupported_value naming the
    # supported set. The UI builds its dropdown from this array
    # (reasoning-mapper.js), so omitting them is what keeps them unselectable.
    it 'offers only the levels the model accepts' do
      levels, = MS.get_model_property(ASTRA, 'reasoning_effort')

      expect(levels).to eq(%w[low medium high xhigh max])
      expect(levels).not_to include('none', 'minimal')
    end

    it 'defaults to a level the model accepts' do
      levels, default = MS.get_model_property(ASTRA, 'reasoning_effort')

      expect(levels).to include(default)
    end
  end

  describe 'endpoint routing' do
    # Live: /v1/chat/completions rejects function tools for this model
    # ("Function tools with reasoning_effort are not supported"). The helper
    # picks the endpoint from api_type, so declaring "responses" is what keeps
    # tool calls off the endpoint that refuses them.
    it 'routes to the Responses API' do
      expect(MS.responses_api?(ASTRA)).to be true
    end

    it 'declares tool capability, which only the Responses API can serve' do
      expect(MS.tool_capability?(ASTRA)).to be true
    end
  end

  describe 'sampling parameters' do
    # Live: temperature and top_p both return 400. The helper drops them for
    # any model where responses_api? is true, so no separate flag is needed —
    # this example pins that the condition it relies on holds.
    it 'is covered by the helper rule that omits sampling parameters' do
      disallow = MS.is_reasoning_model?(ASTRA) ||
                 MS.responses_api?(ASTRA) ||
                 ASTRA.include?('gpt-5')

      expect(disallow).to be true
    end
  end

  describe 'catalog placement' do
    it 'stays out of providerDefaults' do
      # Priced above the 5.6 family, so it is opt-in from the model dropdown
      # rather than a default anyone lands on. providerDefaults is a separate
      # top-level object in model_spec.js — load_spec returns only modelSpec,
      # so reading it from there yields nil and the example would pass on an
      # empty collection without checking anything.
      openai = MS.load_provider_defaults.fetch('openai')

      expect(openai).not_to be_empty

      openai.each do |category, models|
        next unless models.is_a?(Array)

        expect(models).not_to include(ASTRA),
          "providerDefaults.openai.#{category} lists #{ASTRA}, which should be opt-in only."
      end
    end
  end
end
