# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/model_spec'

# The reasoning-effort array in model_spec.js is what the UI builds its
# dropdown from (reasoning-mapper.js), so a level declared here but rejected by
# the API is a level the user can pick and get a 400 from. That happened with
# "minimal" on the gpt-5.6 family: it belongs to the retired gpt-5 tier and no
# current model accepts it.
#
# The table below is what the API itself reports. Asking costs nothing: send a
# level the API knows as a word but the model does not accept -- "minimal" is
# the reliable probe -- and the 400 names that model's supported set:
#
#   curl https://api.openai.com/v1/responses -H "Authorization: Bearer $KEY" \
#     -H 'Content-Type: application/json' \
#     -d '{"model":"MODEL","input":"x","max_output_tokens":16,
#          "reasoning":{"effort":"minimal"}}'
#
# A level the API does not know at all (say "__probe__") fails earlier, in
# parameter validation, and returns the same generic list for every model --
# no per-model information. Recorded 2026-09-05.
RSpec.describe 'OpenAI reasoning effort levels' do
  MS = Monadic::Utils::ModelSpec

  API_REPORTED_LEVELS = {
    'gpt-6-astra' => %w[low medium high xhigh max],
    'gpt-5.6-sol' => %w[none low medium high xhigh max],
    'gpt-5.6-terra' => %w[none low medium high xhigh max],
    'gpt-5.6-luna' => %w[none low medium high xhigh max],
    'gpt-5.5' => %w[none low medium high xhigh],
    'gpt-5.4' => %w[none low medium high xhigh],
    'gpt-5.4-mini' => %w[none low medium high xhigh],
    'gpt-5.4-nano' => %w[none low medium high xhigh],
    'gpt-5.3-codex' => %w[none low medium high xhigh],
    'gpt-5.2' => %w[none low medium high xhigh],
    'gpt-5.1' => %w[none low medium high]
  }.freeze

  API_REPORTED_LEVELS.each do |model, accepted|
    context model do
      let(:declared) do
        spec = MS.get_model_property(model, 'reasoning_effort')
        spec.is_a?(Array) && spec[0].is_a?(Array) ? spec : nil
      end

      it 'is present in the catalog with an effort array' do
        expect(declared).not_to be_nil,
          "#{model} has no reasoning_effort array; if it was removed, drop it from " \
          'API_REPORTED_LEVELS too.'
      end

      it 'offers no level the API rejects' do
        levels, = declared
        expect(levels - accepted).to be_empty,
          "#{model} offers #{(levels - accepted).inspect}, which the API rejects with 400. " \
          "The API reports: #{accepted.inspect}."
      end

      it 'defaults to a level the API accepts' do
        _, default = declared
        expect(accepted).to include(default),
          "#{model} defaults to #{default.inspect}, which the API rejects."
      end
    end
  end

  it 'declares "minimal" nowhere in the gpt-5.6 family or later' do
    # The one that actually shipped broken. Kept as its own example so a
    # regression names the cause rather than a generic set difference.
    %w[gpt-6-astra gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna].each do |model|
      levels, = MS.get_model_property(model, 'reasoning_effort')
      expect(levels).not_to include('minimal'),
        "#{model} offers \"minimal\", which belongs to the retired gpt-5 tier."
    end
  end
end
