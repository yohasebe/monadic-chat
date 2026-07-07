# frozen_string_literal: true

require 'spec_helper'

# Regression (found via live dogfood, invisible to earlier unit tests):
# build_claude_final_tools merges obj["tools"] (tools_param) into the request
# with only tavily filtered out, which re-introduced PTD-hidden conditional tools
# that visible_tools had already dropped — defeating progressive disclosure for
# Claude. apply_claude_skill_visibility re-filters the fully-assembled tool list.
RSpec.describe 'Claude PTD visibility survives tools_param merge (regression)' do
  let(:app_name) { 'ClaudePtdLeakRegression' }

  let(:state) do
    name = app_name
    MonadicDSL.app(name) do
      description 'x'
      llm { provider 'anthropic' }
      tools { import_shared_tools :web_search_tools, visibility: 'conditional' }
    end
  end

  let(:host) { Class.new(MonadicApp) { include ClaudeHelper }.new }
  let(:settings) { state.settings }
  let(:full_tools) { settings[:tools] || settings['tools'] }
  let(:session) { {} }

  def names(tools)
    tools.map do |t|
      f = t[:function] || t['function']
      (f && (f[:name] || f['name'])) || t[:name] || t['name']
    end
  end

  def assemble(filtered)
    # Worst case: obj["tools"] carries the full tool set (the leak source).
    host.send(:build_claude_final_tools, full_tools, filtered)
  end

  it 'removes hidden web tools that tools_param smuggles back into the request' do
    filtered = Monadic::Utils::ProgressiveToolManager.visible_tools(
      app_name: app_name, session: session, app_settings: settings, default_tools: full_tools
    )
    expect(names(filtered)).not_to include('search_web') # visible_tools hides it

    leaked = assemble(filtered)
    expect(names(leaked)).to include('search_web') # bug reproduced: tools_param re-adds it

    fixed = host.send(:apply_claude_skill_visibility, leaked, settings, session, app_name)
    expect(names(fixed)).not_to include('search_web') # fix drops the leak
    expect(names(fixed)).to include('request_tool')   # meta-tool remains visible
  end

  it 'exposes the web tools once the skill is unlocked' do
    Monadic::Utils::ProgressiveToolManager.unlock_request(
      session: session, app_name: app_name, app_settings: settings, request_key: 'web_search_tools'
    )
    filtered = Monadic::Utils::ProgressiveToolManager.visible_tools(
      app_name: app_name, session: session, app_settings: settings, default_tools: full_tools
    )
    fixed = host.send(:apply_claude_skill_visibility, assemble(filtered), settings, session, app_name)
    expect(names(fixed)).to include('search_web')
  end
end
