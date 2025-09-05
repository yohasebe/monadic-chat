# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Content Reader (API smoke)', :api do
  include ProviderMatrixHelper

  it 'extracts and summarizes content-like text' do
    require_run_api!
    text = 'Monadic Chat is a local AI framework that runs tools via Docker.'
    prompt = "Summarize in one sentence: #{text}"
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Content Reader')
        assert_valid_text_response(res)
      end
    end
  end
end

