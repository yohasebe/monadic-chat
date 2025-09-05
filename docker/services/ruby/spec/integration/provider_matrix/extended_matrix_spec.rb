# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

# Provider × App の横断的な最小ケースを増やしたマトリクス
RSpec.describe 'Provider Matrix (extended)', :api do
  include ProviderMatrixHelper

  it 'summarizes a short sentence' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Summarize in one sentence: Monadic Chat is a local AI framework.', app: 'Summary')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end

  it 'produces a python-flavored response for 2+3' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Return a tiny Python snippet to print 2+3. Keep it short.', app: 'Jupyter Notebook')
        assert_valid_text_response(res)
      end
    end
  end

  it 'returns mermaid for A->B' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat('Only output mermaid code: graph TD; A-->B;. No other text.', app: 'Mermaid Grapher')
        assert_valid_text_response(res)
      end
    end
  end
end
