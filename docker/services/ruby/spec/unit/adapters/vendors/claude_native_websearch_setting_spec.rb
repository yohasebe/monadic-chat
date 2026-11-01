# frozen_string_literal: true

require 'spec_helper'

# ANTHROPIC_NATIVE_WEBSEARCH=false must turn native web search off. The config
# reader converts the text "false" into the boolean, so both forms count.
RSpec.describe 'ClaudeHelper#claude_native_websearch_allowed?' do
  let(:helper) { Class.new { include ClaudeHelper }.new }

  def allowed_with(value)
    stub_const('CONFIG', CONFIG.merge('ANTHROPIC_NATIVE_WEBSEARCH' => value))
    helper.send(:claude_native_websearch_allowed?)
  end

  it 'is off when set to false (boolean, as the config reader stores it)' do
    expect(allowed_with(false)).to be(false)
  end

  it 'is off when set to the text false' do
    expect(allowed_with('false')).to be(false)
    expect(allowed_with('FALSE')).to be(false)
  end

  it 'is on when unset or true' do
    expect(allowed_with(nil)).to be(true)
    expect(allowed_with(true)).to be(true)
  end
end
