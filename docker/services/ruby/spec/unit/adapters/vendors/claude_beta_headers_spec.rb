# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# Progressive tool disclosure rewrites the `tools` array between turns
# (conditional tool groups, dynamically unlocked skills). Without the
# mid-conversation-tool-changes beta the whole cached prefix is re-created on
# the turn where the tool set changes; with it, the prefix is read from cache.
# Measured against the live API on 2026-07-25 (Sonnet 5: cache_creation
# 4912 -> 0, cache_read 0 -> 4912). These examples pin that the header is
# actually attached, and that it composes with the other beta flags.
RSpec.describe 'Claude beta headers' do
  MID_TOOL_BETA = 'mid-conversation-tool-changes-2026-07-01'

  let(:helper) do
    Class.new do
      include ClaudeHelper

      def pub_build_headers(model, app)
        headers, _body = send(
          :build_claude_headers_and_body,
          model,
          { 'model' => model },
          app,
          { parameters: {} },
          [],
          { thinking_enabled: false },
          nil,
          'user'
        )
        headers
      end
    end.new
  end

  let(:app_name) { 'SpecBetaApp' }

  before do
    stub_const('APPS', {})
    allow(CONFIG).to receive(:[]).and_call_original
    allow(CONFIG).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
  end

  def betas_for(model, app = app_name)
    (helper.pub_build_headers(model, app)['anthropic-beta'] || '').split(',')
  end

  it 'attaches the mid-conversation tool-changes beta on the current default model' do
    expect(betas_for('claude-sonnet-5')).to include(MID_TOOL_BETA)
  end

  # Anthropic documents the beta for Opus 5 / Opus 4.8 / Fable 5 only, but every
  # catalog model was verified to honor it, and unsupported models ignore the
  # header rather than erroring — so it is sent provider-wide.
  %w[claude-opus-5 claude-opus-4-8 claude-fable-5 claude-haiku-4-5-20251001 claude-sonnet-4-6].each do |model|
    it "attaches it for #{model}" do
      expect(betas_for(model)).to include(MID_TOOL_BETA)
    end
  end

  it 'composes with app-declared betas instead of replacing them' do
    APPS[app_name] = Struct.new(:settings).new({ 'betas' => ['some-other-beta-2026-01-01'] })

    betas = betas_for('claude-sonnet-5')
    expect(betas).to include(MID_TOOL_BETA, 'some-other-beta-2026-01-01')
  end

  it 'emits each beta flag only once' do
    APPS[app_name] = Struct.new(:settings).new({ 'betas' => [MID_TOOL_BETA] })

    betas = betas_for('claude-sonnet-5')
    expect(betas.count(MID_TOOL_BETA)).to eq(1)
  end
end
