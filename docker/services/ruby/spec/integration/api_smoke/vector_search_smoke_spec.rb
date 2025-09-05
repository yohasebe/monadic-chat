# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Vector Search (API smoke)', :api do
  include ProviderMatrixHelper

  it 'answers a basic question about vector databases' do
    require_run_api!
    prompt = 'In one sentence, explain what a vector database is.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Vector Search')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end
end
