# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

# Visual Web Explorer 相当の最小確認（実API）
RSpec.describe 'Visual Web Explorer (API smoke)', :api do
  include ProviderMatrixHelper

  it 'answers a question that commonly requires web context' do
    require_run_api!
    question = 'Who is the current UN Secretary-General? Answer briefly.'
    %w[openai gemini perplexity xai].each do |prov|
      next unless providers_from_env.include?(prov)
      with_provider(prov) do |p|
        res = chat_with_web_context(p, question)
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end

  # 可能な限りウェブ検索を誘発するヒントを付ける
  def chat_with_web_context(p, q)
    hint = 'You may use web search if available.'
    p.chat("#{q} #{hint}")
  end
end

