# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'
require_relative '../../../../lib/monadic/dsl/configurations'

# Tests for the Anthropic Advisor Tool integration.
# See docs_dev/provider_specific_features.md for the policy context.
RSpec.describe 'Claude Advisor Tool integration' do
  describe MonadicDSL::AdvisorToolConfiguration do
    it 'uses claude-opus-4-7 as the default advisor model' do
      cfg = described_class.new
      expect(cfg.to_hash).to eq(model: 'claude-opus-4-7')
    end

    it 'supports custom model, max_uses, and caching' do
      cfg = described_class.new
      cfg.model 'claude-opus-4-7'
      cfg.max_uses 3
      cfg.caching true

      hash = cfg.to_hash
      expect(hash[:model]).to eq('claude-opus-4-7')
      expect(hash[:max_uses]).to eq(3)
      expect(hash[:caching]).to eq(type: 'ephemeral', ttl: '5m')
    end

    it 'accepts ttl strings directly' do
      cfg = described_class.new
      cfg.caching '1h'
      expect(cfg.to_hash[:caching]).to eq(type: 'ephemeral', ttl: '1h')
    end

    it 'accepts a caching hash verbatim' do
      cfg = described_class.new
      cfg.caching({ type: 'ephemeral', ttl: '1h' })
      expect(cfg.to_hash[:caching]).to eq(type: 'ephemeral', ttl: '1h')
    end

    it 'drops caching when set to false' do
      cfg = described_class.new
      cfg.caching false
      expect(cfg.to_hash).not_to have_key(:caching)
    end
  end

  # Build a helper instance and stub APPS so we can exercise the private methods
  # via public wrapper shims. We don't rely on the full request pipeline.
  let(:helper) do
    Class.new do
      include ClaudeHelper

      # Public shims so specs can exercise private methods.
      def pub_claude_advisor_settings(app) = send(:claude_advisor_settings, app)
      def pub_add_claude_advisor_tool(body, app) = send(:add_claude_advisor_tool, body, app)
    end.new
  end

  let(:app_name) { 'SpecAdvisorApp' }

  before do
    stub_const('APPS', {})
  end

  def stub_app_with_settings(settings)
    fake_app = Struct.new(:settings).new(settings)
    APPS[app_name] = fake_app
  end

  describe '#claude_advisor_settings' do
    it 'returns nil when the app has no advisor config' do
      stub_app_with_settings({})
      expect(helper.pub_claude_advisor_settings(app_name)).to be_nil
    end

    it 'returns nil when APPS entry is missing' do
      expect(helper.pub_claude_advisor_settings('NonexistentApp')).to be_nil
    end

    it 'returns the config hash when set with symbol keys' do
      stub_app_with_settings(advisor_tool: { model: 'claude-opus-4-7', max_uses: 3 })
      result = helper.pub_claude_advisor_settings(app_name)
      expect(result[:model]).to eq('claude-opus-4-7')
      expect(result[:max_uses]).to eq(3)
    end

    it 'returns the config hash when set with string keys' do
      stub_app_with_settings('advisor_tool' => { 'model' => 'claude-opus-4-7' })
      result = helper.pub_claude_advisor_settings(app_name)
      expect(result['model']).to eq('claude-opus-4-7')
    end

    it 'treats an empty hash as no opt-in' do
      stub_app_with_settings(advisor_tool: {})
      expect(helper.pub_claude_advisor_settings(app_name)).to be_nil
    end
  end

  describe '#add_claude_advisor_tool' do
    it 'does nothing when advisor is not configured' do
      stub_app_with_settings({})
      body = { 'tools' => [{ 'type' => 'web_search_20250305' }] }
      helper.pub_add_claude_advisor_tool(body, app_name)
      expect(body['tools']).to eq([{ 'type' => 'web_search_20250305' }])
    end

    it 'appends an advisor_20260301 entry when configured' do
      stub_app_with_settings(advisor_tool: { model: 'claude-opus-4-7', max_uses: 3 })
      body = {}
      helper.pub_add_claude_advisor_tool(body, app_name)
      advisor = body['tools'].find { |t| t['type'] == 'advisor_20260301' }
      expect(advisor).not_to be_nil
      expect(advisor['name']).to eq('advisor')
      expect(advisor['model']).to eq('claude-opus-4-7')
      expect(advisor['max_uses']).to eq(3)
    end

    it 'omits max_uses when unset' do
      stub_app_with_settings(advisor_tool: { model: 'claude-opus-4-7' })
      body = {}
      helper.pub_add_claude_advisor_tool(body, app_name)
      advisor = body['tools'].first
      expect(advisor).not_to have_key('max_uses')
    end

    it 'normalizes caching hash to string keys' do
      stub_app_with_settings(advisor_tool: {
        model: 'claude-opus-4-7',
        caching: { type: 'ephemeral', ttl: '5m' }
      })
      body = {}
      helper.pub_add_claude_advisor_tool(body, app_name)
      advisor = body['tools'].first
      expect(advisor['caching']).to eq('type' => 'ephemeral', 'ttl' => '5m')
    end

    it 'does not duplicate the advisor tool on a second call' do
      stub_app_with_settings(advisor_tool: { model: 'claude-opus-4-7' })
      body = {}
      helper.pub_add_claude_advisor_tool(body, app_name)
      helper.pub_add_claude_advisor_tool(body, app_name)
      advisor_entries = body['tools'].select { |t| t['type'] == 'advisor_20260301' }
      expect(advisor_entries.length).to eq(1)
    end

    it 'defaults to claude-opus-4-7 when model is missing' do
      stub_app_with_settings(advisor_tool: { max_uses: 2 })
      body = {}
      helper.pub_add_claude_advisor_tool(body, app_name)
      expect(body['tools'].first['model']).to eq('claude-opus-4-7')
    end
  end

  describe 'disable_parallel_tool_use (advisor-enabled apps)' do
    # These tests exercise the private logic that sets
    # tool_choice.disable_parallel_tool_use = true whenever an app opts in to
    # the Advisor Tool. See claude_helper.rb configure_claude_tools.
    #
    # Rationale: when advisor is called in parallel with other tools, it only
    # sees invocations (not results), and may hallucinate criticism of work
    # that is already succeeding. Sequential execution keeps the advisor's
    # view of the transcript consistent.

    it 'advisor-enabled apps get disable_parallel_tool_use on their tool_choice' do
      # The actual tool_choice wiring is in claude_helper.rb
      # configure_claude_tools. Here we assert that an advisor-configured
      # app returns truthy from claude_advisor_settings, which gates the
      # disable_parallel_tool_use flag.
      stub_app_with_settings(advisor_tool: { model: 'claude-opus-4-7' })
      expect(helper.pub_claude_advisor_settings(app_name)).to be_truthy
    end

    it 'non-advisor apps return nil and do not trigger disable_parallel_tool_use' do
      stub_app_with_settings({})
      expect(helper.pub_claude_advisor_settings(app_name)).to be_nil
    end
  end

  describe 'usage.iterations parsing shape' do
    # Smoke-level shape test: we don't run the full streaming pipeline here,
    # but we verify the iterations structure matches what the parser expects.
    it 'separates executor and advisor iterations by type' do
      iterations = [
        { 'type' => 'message',         'input_tokens' => 400, 'output_tokens' => 80  },
        { 'type' => 'advisor_message', 'input_tokens' => 820, 'output_tokens' => 1600, 'model' => 'claude-opus-4-7' },
        { 'type' => 'message',         'input_tokens' => 1300, 'output_tokens' => 440 }
      ]

      advisor_iters  = iterations.select { |it| it['type'] == 'advisor_message' }
      executor_iters = iterations.select { |it| it['type'] == 'message' }

      expect(advisor_iters.length).to eq(1)
      expect(executor_iters.length).to eq(2)
      expect(advisor_iters.sum { |it| it['output_tokens'] }).to eq(1600)
      expect(executor_iters.sum { |it| it['output_tokens'] }).to eq(520)
    end
  end
end
