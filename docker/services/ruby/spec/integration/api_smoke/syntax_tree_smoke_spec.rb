# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Syntax Tree (API smoke)', :api do
  include ProviderMatrixHelper

  it 'produces a tiny JSON AST for 1+2' do
    require_run_api!
    prompt = 'Describe the structure of the expression 1+2 briefly (e.g., as JSON).'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Syntax Tree')
        assert_valid_text_response(res)
      end
    end
  end
end
