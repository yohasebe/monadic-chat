# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Jupyter Notebook (API smoke)', :api do
  include ProviderMatrixHelper

  it 'can produce a minimal Python code cell', timeout: 120 do
    require_run_api!
    prompt = 'Return a tiny Python snippet to print 2+3. Keep it short.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        # Jupyter operations may take longer than standard chat
        res = p.chat(prompt, app: 'Jupyter Notebook')
        assert_valid_text_response(res)
      end
    end
  end
end
