# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Web Search (API smoke)', :api do
  include ProviderMatrixHelper

  # Minimal check that providers answer a query that typically requires fresh knowledge.
  it 'returns a non-empty answer to a timely query' do
    require_run_api!
    timely_question = 'What year was the latest FIFA World Cup held? Answer briefly.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        unless p.supports_web_search?
          puts "[skip] provider=#{prov} doesn't support native/assisted web_search"
          next
        end
        res = p.web_search(timely_question, app: 'Visual Web Explorer')
        assert_valid_text_response(res)
      end
    end
  end
end
