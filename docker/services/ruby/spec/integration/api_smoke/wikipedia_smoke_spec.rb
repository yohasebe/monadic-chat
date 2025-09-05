# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Wikipedia (API smoke)', :api do
  include ProviderMatrixHelper

  it 'gives a one-sentence summary for a well-known topic' do
    require_run_api!
    prompt = 'Give a one-sentence summary of Albert Einstein.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Wikipedia')
        assert_valid_text_response(res)
      end
    end
  end
end
