# frozen_string_literal: true

require 'spec_helper'

# Regression: ToolConfiguration#to_h runs once per configuration — the app's own
# `tools do` block AND each auto-injected group (file_operations, library_search),
# each via its own ToolConfiguration. to_h used to OVERWRITE
# progressive_tools[:all_tool_names]/:always_visible/:conditional, so a later
# file_operations injection erased the app's own conditional tools from the PTD
# metadata. With the metadata dropped, visible_tools no longer recognized those
# tools as managed and silently left them ALWAYS visible. to_h now unions.
RSpec.describe 'MonadicDSL progressive_tools metadata merge (regression)' do
  # An app that declares a conditional skill but does NOT import file_operations
  # itself — this is what triggers the injection pass that exposed the bug.
  let(:state) do
    MonadicDSL.app('PtdMergeRegression') do
      description 'x'
      llm { provider 'openai' }
      tools { import_shared_tools :web_search_tools, visibility: 'conditional' }
    end
  end

  def pt(state)
    state.settings[:progressive_tools] || {}
  end

  def tool_names(state)
    tools = state.settings[:tools]
    arr = tools.is_a?(Hash) ? (tools['function_declarations'] || tools[:function_declarations] || []) : Array(tools)
    arr.map { |t| (t[:function] && t[:function][:name]) || (t['function'] && t['function']['name']) || t[:name] || t['name'] }.compact
  end

  it 'keeps the app-declared conditional tools in all_tool_names after file_operations is injected' do
    names = Array(pt(state)[:all_tool_names])
    expect(names).to include('search_web', 'fetch_web_content', 'tavily_search', 'tavily_fetch')
    # The injected always-visible file ops are also present: union, not overwrite.
    expect(names).to include('read_file_from_shared_folder')
  end

  it 'keeps the app-declared conditional tools in the conditional metadata' do
    cond_names = Array(pt(state)[:conditional]).map { |c| c[:name] }
    expect(cond_names).to include('search_web', 'tavily_search')
  end

  it 'marks request_tool always-visible and does not duplicate it in the tools array' do
    expect(Array(pt(state)[:always_visible])).to include('request_tool')
    expect(tool_names(state).count('request_tool')).to eq(1)
  end
end
