# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Translate (API smoke)', :api do
  include ProviderMatrixHelper

  it 'translates a simple word to Japanese' do
    require_run_api!
    prompt = 'Translate the word "Hello" into Japanese. Answer with one word only.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Translate')
        assert_valid_text_response(res)
      end
    end
  end
end
