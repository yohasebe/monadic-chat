# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Research Assistant (API smoke)', :api do
  include ProviderMatrixHelper

  it 'returns brief findings with at least one sentence' do
    require_run_api!
    prompt = 'In one or two sentences, summarize the benefits of vector databases.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Research Assistant')
        expect(res[:text]).to be_a(String)
        expect(res[:text].strip.length).to be > 10
      end
    end
  end
end
