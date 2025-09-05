# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Chat (API smoke)', :api do
  include ProviderMatrixHelper

  it 'responds minimally for enabled providers' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('ping', app: 'Chat')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end
end
