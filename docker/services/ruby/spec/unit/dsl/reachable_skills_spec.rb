# frozen_string_literal: true

require 'spec_helper'
# Require the implementation under test directly so the SSOT-drift example
# below does not depend on another spec having loaded ConduitAgent first
# (it referenced Monadic::MCP::ConduitAgent::SAFE_GROUPS with no require and
# failed with NameError when run in isolation).
require_relative '../../../lib/monadic/mcp/conduit_agent'
require_relative '../../../lib/monadic/shared_tools/registry'

# `reachable_skills` is DSL sugar for declaring skill groups an app can reach for
# mid-conversation: imported as `conditional` (hidden until the model unlocks them
# via the request_tool menu). `:safe` expands to Registry.safe_groups (the SSOT).
RSpec.describe 'MonadicDSL reachable_skills sugar' do
  def groups_of(state)
    Array(state.settings[:imported_tool_groups])
  end

  def conditional_names(state)
    Array((state.settings[:progressive_tools] || {})[:conditional]).map { |c| c[:name] }
  end

  it 'imports explicitly named groups as conditional' do
    state = MonadicDSL.app('ReachExplicit') do
      description 'x'
      llm { provider 'openai' }
      tools { reachable_skills :web_search_tools }
    end
    entry = groups_of(state).find { |g| g[:name] == :web_search_tools }
    expect(entry).not_to be_nil
    expect(entry[:visibility]).to eq('conditional')
    expect(conditional_names(state)).to include('search_web')
  end

  it 'expands :safe to every read-only group in Registry.safe_groups, all conditional' do
    state = MonadicDSL.app('ReachSafe') do
      description 'x'
      llm { provider 'openai' }
      tools { reachable_skills :safe }
    end
    imported = groups_of(state)
    MonadicSharedTools::Registry.safe_groups.each do |g|
      entry = imported.find { |x| x[:name] == g }
      expect(entry).not_to be_nil, "expected safe group #{g} to be imported"
      expect(entry[:visibility]).to eq('conditional')
    end
  end

  it 'never exposes safe-pool tools as always-visible (they stay hidden until requested)' do
    state = MonadicDSL.app('ReachSafeHidden') do
      description 'x'
      llm { provider 'openai' }
      tools { reachable_skills :safe }
    end
    always = Array((state.settings[:progressive_tools] || {})[:always_visible])
    # request_tool + injected file_operations may be always-visible, but no
    # reachable skill tool should be.
    expect(always).not_to include('search_web', 'analyze_image')
  end

  it 'keeps the Conduit agent allowlist derived from the Registry SSOT (no drift)' do
    expect(Monadic::MCP::ConduitAgent::SAFE_GROUPS).to eq(
      MonadicSharedTools::Registry.safe_groups.map(&:to_s)
    )
  end
end
