# frozen_string_literal: true

require 'spec_helper'

# Phase 9: shared-folder file operations are a universal default — every app
# gets read/write/list tools so ${SHARED} is actionable everywhere. The
# injection mirrors inject_library_search! and dedupes against apps that already
# import :file_operations.
RSpec.describe 'MonadicDSL universal file_operations injection' do
  def tool_names(state)
    tools = state.settings[:tools]
    arr = tools.is_a?(Hash) ? (tools[:function_declarations] || tools['function_declarations'] || []) : Array(tools)
    arr.map { |t| (t[:function] && t[:function][:name]) || (t['function'] && t['function']['name']) || t[:name] || t['name'] }.compact
  end

  it 'adds read/write file tools to an app that declares no tools block' do
    state = MonadicDSL.app('FileOpsInjectNoTools') do
      description 'x'
      llm { provider 'openai' }
    end
    names = tool_names(state)
    expect(names).to include('read_file_from_shared_folder', 'write_file_to_shared_folder')
  end

  it 'does not duplicate when the app already imports :file_operations' do
    state = MonadicDSL.app('FileOpsInjectExplicit') do
      description 'x'
      llm { provider 'openai' }
      tools { import_shared_tools :file_operations, visibility: 'always' }
    end
    expect(tool_names(state).count('write_file_to_shared_folder')).to eq(1)
  end

  it 'injects into the Gemini function_declarations tool shape too' do
    state = MonadicDSL.app('FileOpsInjectGemini') do
      description 'x'
      llm { provider 'gemini' }
    end
    expect(tool_names(state)).to include('write_file_to_shared_folder')
  end

  it 'records :file_operations in imported_tool_groups' do
    state = MonadicDSL.app('FileOpsInjectGroups') do
      description 'x'
      llm { provider 'openai' }
    end
    groups = (state.settings[:imported_tool_groups] || []).map { |g| g[:name] }
    expect(groups).to include(:file_operations)
  end
end
