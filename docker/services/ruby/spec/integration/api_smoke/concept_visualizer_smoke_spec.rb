# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Concept Visualizer (API smoke)', :api do
  include ProviderMatrixHelper

  it 'lists 3 simple concepts for "machine learning"' do
    require_run_api!
    prompt = 'List three key concepts of machine learning as bullet points.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt)
        assert_valid_text_response(res)
      end
    end
  end
end
