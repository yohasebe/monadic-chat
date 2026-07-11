# frozen_string_literal: true

require 'spec_helper'

# analyze_image gained an optional `detail:` fidelity parameter
# (low/high/auto/original — enum verified against the live OpenAI API
# 2026-07-10; "original" preserves full resolution). Defaults must stay
# unchanged: no detail field is sent unless explicitly requested, and only
# whitelisted values pass through (typos must not reach the API).
RSpec.describe 'analyze_image detail parameter' do
  let(:agent_src) do
    File.read(File.expand_path('../../../lib/monadic/agents/image_analysis_agent.rb', __dir__))
  end

  it 'threads detail from the helper into the agent and the OpenAI body' do
    helper_src = File.read(File.expand_path('../../../lib/monadic/adapters/file_analysis_helper.rb', __dir__))
    expect(helper_src).to include('detail: nil')
    expect(helper_src).to include('detail: detail')
    expect(agent_src).to include('def image_analysis_agent(message:, image_path:, detail: nil)')
  end

  it 'whitelists the four live-verified values and omits the field otherwise' do
    expect(agent_src).to match(/%w\[low high auto original\]\.include\?\(detail\.to_s\)/)
  end

  it 'declares the optional detail parameter in both tool registries' do
    ia = File.read(File.expand_path('../../../lib/monadic/shared_tools/image_analysis.rb', __dir__))
    reg = File.read(File.expand_path('../../../lib/monadic/shared_tools/registry.rb', __dir__))
    expect(ia).to include('enum: ["low", "high", "auto", "original"]')
    expect(reg).to match(/name: :detail,\s*\n\s*type: "string"/)
    # message/image_path remain the only required params
    expect(ia).to include('required: ["message", "image_path"]')
  end
end
