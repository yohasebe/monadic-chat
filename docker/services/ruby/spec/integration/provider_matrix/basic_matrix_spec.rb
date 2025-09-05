# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Provider Matrix (basic)', :api do
  include ProviderMatrixHelper

  it 'answers a ping across providers' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('ping', app: 'Ping')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end

  it 'translates hello to French' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Translate "Hello" to French. Answer briefly.', app: 'Translate')
        assert_valid_text_response(res)
      end
    end
  end

  it 'returns a mermaid snippet for A->B' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Output mermaid code for A->B as graph TD; A-->B; only code.', app: 'Mermaid Grapher')
        assert_valid_text_response(res)
      end
    end
  end
end
