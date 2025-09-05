# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Code Interpreter (API smoke)', :api do
  include ProviderMatrixHelper

  it 'computes a tiny math task' do
    require_run_api!
    prompt = 'Compute 2+2 and answer only with the number.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        unless p.supports_code_interpreter?
          puts "[skip] provider=#{prov} doesn't support code_interpreter"
          next
        end
        res = p.code_interpret(prompt, app: 'Code Interpreter')
        expect(res[:text]).to be_a(String)
        # Accept contains 4 (loose check to avoid locale/format issues)
        expect(res[:text]).to match(/\b4\b/)
        expect(res[:text]).not_to match(/API Error/i)
      end
    end
  end
end
