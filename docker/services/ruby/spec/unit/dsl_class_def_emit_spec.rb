# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../lib/monadic/dsl'
require_relative '../../lib/monadic/dsl/loader'

# Regression: class_def emit coverage for per-app setting keys.
#
# `lib/monadic/dsl.rb` has a hand-written class_def generator that
# manually emits each settings key with `if state.settings[:key]` or
# `unless .nil?` guards. Every new feature (compaction, advisor_tool,
# context_management, etc.) requires adding a new emit line here. If a
# developer forgets, the MDSL value silently never reaches the runtime
# class and the feature appears to do nothing.
#
# This spec round-trips each keyed feature through a temporary MDSL file
# (DSL method → AppState → class_def → generated class → @settings) to
# guarantee each setting is both emitted AND preserved as written. New
# features should add a describe block here.
RSpec.describe 'MonadicDSL class_def emit coverage' do
  before(:all) do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
  end

  def load_mdsl_body(const_name, body, llm_extras: '')
    file = Tempfile.new([const_name, '.mdsl'])
    file.write(<<~MDSL)
      app "#{const_name}" do
        description "class_def emit spec fixture"
        icon "fa-flask"
        display_name "#{const_name}"

        llm do
          provider "openai"
          #{llm_extras}
        end

        #{body}

        features do
          disabled false
        end
      end
    MDSL
    file.close
    MonadicDSL::Loader.load(file.path)
    Object.const_get(const_name).instance_variable_get(:@settings)
  ensure
    file&.unlink
  end

  describe 'compaction' do
    it 'emits a Hash when set via `compaction do compact_threshold N end`' do
      settings = load_mdsl_body('EmitCompactionHash', 'compaction do; compact_threshold 180_000; end')
      value = settings[:compaction] || settings['compaction']
      expect(value).to be_a(Hash)
      expect(value[:compact_threshold] || value['compact_threshold']).to eq(180_000)
    end

    it 'emits the default Hash when set via `compaction` alone' do
      settings = load_mdsl_body('EmitCompactionDefault', 'compaction')
      value = settings[:compaction] || settings['compaction']
      expect(value).to be_a(Hash)
      expect(value[:compact_threshold] || value['compact_threshold']).to eq(150_000)
    end

    it 'emits literal false when set via `compaction false`' do
      settings = load_mdsl_body('EmitCompactionFalse', 'compaction false')
      value = settings[:compaction]
      value = settings['compaction'] if value.nil?
      expect(value).to eq(false)
    end

    it 'leaves :compaction unset when not specified at all' do
      settings = load_mdsl_body('EmitCompactionUnset', '# no compaction block')
      expect(settings).not_to have_key(:compaction)
      expect(settings).not_to have_key('compaction')
    end
  end

  describe 'context_management' do
    it 'emits a Hash when set via `context_management do edits [...] end`' do
      body = <<~DSL
        context_management do
          edits [{ type: "clear_tool_uses_20250919", trigger: { type: "input_tokens", value: 80_000 } }]
        end
      DSL
      settings = load_mdsl_body('EmitContextManagementHash', body)
      value = settings[:context_management] || settings['context_management']
      expect(value).to be_a(Hash)
      edits = value[:edits] || value['edits']
      expect(edits).to be_an(Array)
      expect(edits.first[:type] || edits.first['type']).to eq('clear_tool_uses_20250919')
    end

    it 'emits literal false when set via `context_management false`' do
      settings = load_mdsl_body('EmitContextManagementFalse', 'context_management false')
      value = settings[:context_management]
      value = settings['context_management'] if value.nil?
      expect(value).to eq(false)
    end

    it 'leaves :context_management unset when not specified' do
      settings = load_mdsl_body('EmitContextManagementUnset', '# no context_management block')
      expect(settings).not_to have_key(:context_management)
      expect(settings).not_to have_key('context_management')
    end
  end

  describe 'advisor_tool' do
    it 'emits advisor_tool settings when set via `advisor_tool do ... end`' do
      body = <<~DSL
        advisor_tool do
          model    "claude-opus-4-6"
          max_uses 2
          caching  true
        end
      DSL
      settings = load_mdsl_body('EmitAdvisorTool', body)
      value = settings[:advisor_tool] || settings['advisor_tool']
      expect(value).not_to be_nil
      expect(value[:model] || value['model']).to eq('claude-opus-4-6')
      expect(value[:max_uses] || value['max_uses']).to eq(2)
    end
  end

  describe 'betas (nested in llm block)' do
    it 'emits per-app betas when set via `betas [...]` inside llm do' do
      settings = load_mdsl_body(
        'EmitBetas',
        '# betas set in llm_extras',
        llm_extras: 'betas ["beta-header-a", "beta-header-b"]'
      )
      value = settings[:betas] || settings['betas']
      expect(value).to eq(['beta-header-a', 'beta-header-b'])
    end
  end

  describe 'false-sentinel preservation invariant' do
    # The `unless settings[:key].nil?` guard (used by compaction and
    # context_management) preserves `false` through emit. Without it,
    # `if settings[:key]` would treat false as falsy and skip the emit,
    # converting user-visible opt-out into silent default-on behavior.
    # Use Regexp.escape to avoid the `[...]` being parsed as a char class.
    let(:dsl_source) do
      File.read(File.expand_path('../../lib/monadic/dsl.rb', __dir__))
    end

    it 'uses `unless nil?` guard pattern for compaction false-sentinel key' do
      pattern = Regexp.new('unless\s+state\.settings' + Regexp.escape('[:compaction]') + '\.nil\?')
      expect(dsl_source).to match(pattern)
    end

    it 'uses `unless nil?` guard pattern for context_management false-sentinel key' do
      pattern = Regexp.new('unless\s+state\.settings' + Regexp.escape('[:context_management]') + '\.nil\?')
      expect(dsl_source).to match(pattern)
    end
  end
end
