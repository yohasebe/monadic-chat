# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Image generation (API media)', :api, :media do
  include ProviderMatrixHelper

  it 'creates a tiny image (cost-guarded, real API)' do
    require_run_media!
    with_provider(:openai) do |p|
      img = p.image_generate_api('a yellow square', size: '256x256')
      if img.is_a?(String)
        raise "Image API error: #{img}"
      end
      if img[:bytes]
        expect(img[:bytes]).to be_a(String)
        expect(img[:bytes].bytesize).to be > 0
      elsif img[:url]
        expect(img[:url]).to be_a(String)
        expect(img[:url]).to match(%r{^https?://})
      else
        raise 'Unexpected image result shape'
      end
    end
  end
end
