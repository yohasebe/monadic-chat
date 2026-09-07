# frozen_string_literal: true

require_relative '../../../spec_helper'

# session[:monadic_state] holds three unrelated things under one roof: app
# namespaces shaped {key => {data, version, updated_at}}, the Context Panel's
# own structures, and the privacy registry. The import route walks every
# top-level key as if it were an app namespace and reads ["data"] from each
# value, so exporting the panel's plain hash there made a normal
# Language Practice Plus session fail to import with
# "no implicit conversion of String into Integer".
#
# The import route already had a field for the panel — `session_context` — so
# the fix is to export into it rather than to loosen the app-state contract.
# These examples pin both halves and the recovery path for files written
# before the split.
RSpec.describe 'Export/import round trip for session state' do
  # The export halves, loaded without the WebSocket handler stack.
  let(:exporter) do
    src = File.read(
      File.expand_path('../../../../lib/monadic/utils/websocket/privacy_handler.rb', __dir__)
    )
    reserved = src[/^  PRIVACY_STATE_RESERVED_KEYS = %w\[.*?\]\.freeze/m]
    methods = %w[privacy_export_monadic_state privacy_export_session_context]
              .map { |name| src[/private def #{name}.*?^  end/m] }

    expect(reserved).to be_a(String), 'PRIVACY_STATE_RESERVED_KEYS has moved'
    expect(methods).to all(be_a(String))

    Module.new.tap do |m|
      m.module_eval("#{reserved}\n#{methods.join("\n").gsub('private def', 'def self.')}")
    end
  end

  # The import route's restore block, read from source so the test cannot
  # drift from what runs.
  let(:import_code) do
    lines = File.readlines(
      File.expand_path('../../../../lib/monadic/routes/session_routes.rb', __dir__)
    )
    start = lines.index { |l| l.strip == 'if json_data["monadic_state"]' }
    finish = lines.index { |l| l.include?('Restored session_context with') }

    expect(start).to be_a(Integer), 'the monadic_state restore block has moved'
    expect(finish).to be_a(Integer), 'the session_context restore block has moved'

    lines[start, (finish - start) + 2].join
  end

  def import(json_data, code)
    session = {}
    # ExtraLogger is called inside the block; the surrounding module is not
    # loaded here.
    stub = Module.new { def self.log(*); end }
    Object.const_set(:StubLogger, stub) unless Object.const_defined?(:StubLogger)
    eval(code.gsub('Monadic::Utils::ExtraLogger', 'StubLogger')) # rubocop:disable Security/Eval
    session
  end

  let(:app_state) { { 'notes' => { data: %w[x], version: 1, updated_at: 't' } } }
  let(:panel) { { '_turn_count' => 2, 'tips' => [{ 'text' => 'Use past tense', 'turn' => 1 }] } }

  describe 'a session carrying both app state and a Context Panel' do
    let(:session) do
      {
        monadic_state: {
          'MyApp' => app_state,
          conversation_context: panel,
          privacy: { registry: { '<<P>>' => 'secret' } }
        }
      }
    end

    let(:payload) do
      out = {}
      state = exporter.privacy_export_monadic_state(session)
      out['monadic_state'] = state if state
      out.merge(exporter.privacy_export_session_context(session))
    end

    it 'exports the panel under its own field, not as an app namespace' do
      expect(payload['session_context']).to eq(panel)
      expect(payload['monadic_state']).not_to have_key('conversation_context')
    end

    it 'still exports the app namespace' do
      # Positive control: without this, "the panel is not in monadic_state"
      # would also pass on an export that dropped everything.
      expect(payload['monadic_state']).to have_key('MyApp')
    end

    it 'never exports the privacy registry' do
      expect(JSON.generate(payload)).not_to include('secret')
    end

    it 'imports without raising' do
      restored = import(JSON.parse(JSON.generate(payload)), import_code)

      expect(restored[:monadic_state]['MyApp']['notes'][:data]).to eq(%w[x])
      expect(restored[:monadic_state][:conversation_context]).to eq(panel)
    end
  end

  describe 'a file written before the split' do
    # The panel sits inside monadic_state, which is what used to raise.
    let(:legacy) do
      {
        'monadic_state' => {
          'MyApp' => { 'notes' => { 'data' => %w[x], 'version' => 1, 'updated_at' => 't' } },
          'conversation_context' => panel
        }
      }
    end

    it 'imports instead of failing the whole session' do
      expect { import(legacy, import_code) }.not_to raise_error
    end

    it 'recovers the panel rather than silently dropping it' do
      restored = import(legacy, import_code)

      expect(restored[:monadic_state][:conversation_context]).to eq(panel)
      expect(restored[:monadic_state]['MyApp']['notes'][:data]).to eq(%w[x])
    end
  end

  describe 'the export path wires the panel in' do
    # The examples above call the export halves directly, so they keep passing
    # if the payload assembly stops merging session_context.
    let(:source) do
      File.read(
        File.expand_path('../../../../lib/monadic/utils/websocket/privacy_handler.rb', __dir__)
      )
    end

    it 'builds the panel fields' do
      expect(source).to include('session_context = privacy_export_session_context(session)')
    end

    it 'merges them into both the plain and the encrypted payload' do
      expect(source.scan('payload.merge!(session_context)').size).to eq(2)
    end
  end
end
