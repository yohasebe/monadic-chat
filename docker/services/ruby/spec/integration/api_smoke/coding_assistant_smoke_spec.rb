# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Coding Assistant (API smoke)', :api do
  include ProviderMatrixHelper

  it 'returns a minimal Ruby function skeleton' do
    require_run_api!
    prompt = 'Write a Ruby method named add that returns a+b. Keep it brief.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Coding Assistant')
        assert_valid_text_response(res)
      end
    end
  end
end
