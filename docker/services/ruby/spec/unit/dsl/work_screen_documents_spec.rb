# frozen_string_literal: true

require 'spec_helper'

# An app that puts its work on the work screen (its work_screen feature)
# gets write_section; any other app does not.
RSpec.describe 'MonadicDSL work_screen feature' do
  def groups_of(state)
    Array(state.settings[:imported_tool_groups]).map { |g| g[:name] }
  end

  it 'gives an app with a known work_screen way the documents tools' do
    state = MonadicDSL.app('WorkScreenDrafts') do
      description 'x'
      llm { provider 'openai' }
      features { work_screen 'drafts' }
    end
    expect(groups_of(state).count(:documents)).to eq(1)
  end

  it 'gives them to no other app' do
    plain = MonadicDSL.app('WorkScreenNone') do
      description 'x'
      llm { provider 'openai' }
    end
    odd = MonadicDSL.app('WorkScreenOdd') do
      description 'x'
      llm { provider 'openai' }
      features { work_screen 'nothing like this' }
    end
    expect(groups_of(plain)).not_to include(:documents)
    expect(groups_of(odd)).not_to include(:documents)
  end

  it 'imports them once for an app that imports them itself' do
    state = MonadicDSL.app('WorkScreenOwn') do
      description 'x'
      llm { provider 'openai' }
      features { work_screen 'code' }
      tools { import_shared_tools :documents, visibility: 'always' }
    end
    expect(groups_of(state).count(:documents)).to eq(1)
  end
end
