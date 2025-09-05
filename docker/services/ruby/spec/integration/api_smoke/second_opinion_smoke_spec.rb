# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Second Opinion (API smoke)', :api do
  include ProviderMatrixHelper

  it 'provides independent responses across providers' do
    require_run_api!
    texts = []
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Give a 1-sentence summary of the Eiffel Tower.', app: 'Second Opinion')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
        texts << [prov, res[:text]]
      end
    end
    expect(texts).not_to be_empty
  end
end
