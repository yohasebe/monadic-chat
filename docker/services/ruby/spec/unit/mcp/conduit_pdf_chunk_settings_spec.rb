# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/mcp/conduit'

# PDF_RAG_TOKENS / PDF_RAG_OVERLAP_LINES set in ~/monadic/config/env reach
# CONFIG, not the constants (which are set before the file is loaded).
RSpec.describe 'Conduit PDF chunk settings' do
  let(:conduit) { Monadic::MCP::Conduit }

  def with_config(values)
    stub_const('CONFIG', CONFIG.merge(values))
    yield
  end

  it 'uses the values from CONFIG' do
    with_config('PDF_RAG_TOKENS' => 6000, 'PDF_RAG_OVERLAP_LINES' => 6) do
      expect(conduit.kb_chunk_tokens).to eq(6000)
      expect(conduit.kb_overlap_lines).to eq(6)
    end
  end

  it 'accepts values written as text' do
    with_config('PDF_RAG_TOKENS' => '5000', 'PDF_RAG_OVERLAP_LINES' => '2') do
      expect(conduit.kb_chunk_tokens).to eq(5000)
      expect(conduit.kb_overlap_lines).to eq(2)
    end
  end

  it 'falls back to the defaults when unset or invalid' do
    with_config('PDF_RAG_TOKENS' => nil, 'PDF_RAG_OVERLAP_LINES' => 'many') do
      expect(conduit.kb_chunk_tokens).to eq(4000)
      expect(conduit.kb_overlap_lines).to eq(4)
    end
  end
end
