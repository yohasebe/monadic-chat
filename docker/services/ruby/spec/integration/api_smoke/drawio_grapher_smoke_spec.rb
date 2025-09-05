# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'DrawIO Grapher (API smoke)', :api do
  include ProviderMatrixHelper

  it 'outputs a minimal draw.io XML snippet' do
    require_run_api!
    prompt = 'Create a minimal draw.io XML (mxGraphModel) with two nodes A and B connected. Keep it short.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'DrawIO Grapher')
        assert_valid_text_response(res)
      end
    end
  end
end
