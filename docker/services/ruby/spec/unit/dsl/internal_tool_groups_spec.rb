# frozen_string_literal: true

require 'spec_helper'
require 'active_support'
require 'active_support/core_ext/hash/indifferent_access'

# A group imported with visibility "internal" is kept for the app's own use:
# its module and the state it declares stay, and its tools are never offered
# to the model, whatever else names them.
RSpec.describe 'Internal tool groups' do
  CONTEXT_TOOLS = %w[get_context update_context remove_from_context clear_context].freeze

  def names_of(tools)
    tools = tools['function_declarations'] || tools[:function_declarations] if tools.is_a?(Hash)
    Array(tools).map do |t|
      f = t[:function] || t['function']
      (f && (f[:name] || f['name'])) || t[:name] || t['name']
    end
  end

  # As the app loader makes each app (lib/monadic.rb): the class settings,
  # with indifferent access.
  def instance_of(klass)
    app = klass.new
    app.settings = ActiveSupport::HashWithIndifferentAccess.new(klass.instance_variable_get(:@settings))
    app
  end

  def build(name, provider: 'openai', &tools_block)
    MonadicDSL.app(name) do
      description 'x'
      llm { provider provider }
      tools(&tools_block)
    end
  end

  describe 'the DSL' do
    it 'offers none of the group\'s tools and records them as internal' do
      state = build('InternalOnlyOpenAI') { import_shared_tools :session_context, visibility: 'internal' }
      offered = names_of(state.settings[:tools])
      expect(offered & CONTEXT_TOOLS).to be_empty
      expect(state.settings[:internal_tool_names]).to match_array(CONTEXT_TOOLS)
      expect(state.settings[:internal_tool_groups]).to eq([:session_context])
      expect(Array(state.settings[:imported_tool_groups]).map { |g| g[:name] }).not_to include(:session_context)
    end

    it 'leaves the tools out of the progressive metadata, so no unlock can bring them back' do
      state = build('InternalPtdOpenAI') do
        import_shared_tools :file_operations, visibility: 'conditional'
        import_shared_tools :session_context, visibility: 'internal'
      end
      pt = state.settings[:progressive_tools] || {}
      listed = Array(pt[:all_tool_names]) + Array(pt[:always_visible]) + Array(pt[:conditional]).map { |c| c[:name] }
      expect(listed & CONTEXT_TOOLS).to be_empty
    end

    it 'keeps the tools out whichever import of the same group comes first' do
      before = build('InternalAfterOpenAI') do
        import_shared_tools :session_context, visibility: 'always'
        import_shared_tools :session_context, visibility: 'internal'
      end
      after = build('InternalBeforeOpenAI') do
        import_shared_tools :session_context, visibility: 'internal'
        import_shared_tools :session_context, visibility: 'always'
      end
      expect(names_of(before.settings[:tools]) & CONTEXT_TOOLS).to be_empty
      expect(names_of(after.settings[:tools]) & CONTEXT_TOOLS).to be_empty
      [before, after].each do |state|
        expect(Array(state.settings[:imported_tool_groups]).map { |g| g[:name].to_s }).not_to include('session_context')
      end
    end

    it 'includes the group\'s module, and the state names no load tool' do
      build('InternalModuleOpenAI') { import_shared_tools :session_context, visibility: 'internal' }
      app = instance_of(InternalModuleOpenAI)
      expect(app).to respond_to(:update_context)
      declared = app.send(:state_for_model, { messages: [] })
      expect(declared[:load_tool]).to be_nil
    end

    it 'offers the tools named in offer: and keeps the rest internal' do
      state = build('InternalOfferOpenAI') do
        import_shared_tools :session_context, visibility: 'internal', offer: %w[remove_from_context clear_context]
      end
      expect(names_of(state.settings[:tools]) & CONTEXT_TOOLS).to match_array(%w[remove_from_context clear_context])
      expect(state.settings[:internal_tool_names]).to match_array(%w[get_context update_context])
    end

    it 'leaves a public import as it was' do
      build('PublicContextOpenAI') { import_shared_tools :session_context, visibility: 'always' }
      app = instance_of(PublicContextOpenAI)
      expect(names_of(app.settings[:tools])).to include('update_context')
      expect(app.send(:state_for_model, { messages: [] })[:load_tool]).to eq('get_context')
    end
  end

  describe 'the Chat apps' do
    chat_dir = File.expand_path('../../../apps/chat', __dir__)

    Dir.glob(File.join(chat_dir, 'chat_*.mdsl')).sort.each do |path|
      it "add notes after the reply and offer only removing them: #{File.basename(path)}" do
        state = eval(File.read(path), TOPLEVEL_BINDING, path) # rubocop:disable Security/Eval
        expect(names_of(state.settings[:tools]) & CONTEXT_TOOLS).to match_array(%w[remove_from_context clear_context])
        expect(state.settings[:internal_tool_names]).to match_array(%w[get_context update_context])
        expect(state.features[:keep_notes]).to be(true)
        expect(Array(state.settings[:imported_tool_groups]).map { |g| g[:name].to_s }).not_to include('session_context')
        prompt = state.settings[:initial_prompt].to_s
        %w[get_context update_context].each { |tool| expect(prompt).not_to include(tool) }
      end
    end
  end

  describe 'the request' do
    let(:guard) { Monadic::Utils::ToolDispatchGuard }

    it 'removes named tools in every provider shape and keeps the rest' do
      openai = [{ 'type' => 'function', 'function' => { 'name' => 'update_context' } },
                { 'type' => 'function', 'function' => { 'name' => 'read_file' } }, { 'type' => 'web_search' }]
      responses = [{ 'type' => 'function', 'name' => 'update_context' }, { 'type' => 'function', 'name' => 'read_file' }]
      claude = [{ 'name' => 'update_context', 'input_schema' => {} }, { 'name' => 'read_file', 'input_schema' => {} }]
      gemini = [{ 'function_declarations' => [{ 'name' => 'update_context' }, { 'name' => 'read_file' }] },
                { 'function_declarations' => [{ 'name' => 'clear_context' }] }, { 'google_search' => {} }]
      [openai, responses, claude, gemini].each do |tools|
        left = guard.without(tools, CONTEXT_TOOLS)
        expect(guard.offered_names(left).to_a).to eq(['read_file'])
      end
      expect(guard.without(gemini, CONTEXT_TOOLS).last).to eq({ 'google_search' => {} })
      camel = [{ 'functionDeclarations' => [{ 'name' => 'update_context' }, { 'name' => 'read_file' }] }]
      expect(guard.offered_names(guard.without(camel, CONTEXT_TOOLS)).to_a).to eq(['read_file'])
      expect(guard.without({ 'name' => 'update_context' }, CONTEXT_TOOLS)).to be_nil
      expect(guard.without({ 'name' => 'read_file' }, CONTEXT_TOOLS)).to eq({ 'name' => 'read_file' })
      expect(guard.without(openai, CONTEXT_TOOLS).last).to eq({ 'type' => 'web_search' })
    end

    it 'never offers an internal tool, also one the request was built with' do
      helper = Class.new { include BaseVendorHelper }.new
      stub_const('APPS', { 'ChatSpec' => Struct.new(:settings).new({ internal_tool_names: CONTEXT_TOOLS }) })
      body = { 'tools' => [{ 'type' => 'function', 'function' => { 'name' => 'update_context' } }], 'tool_choice' => 'auto' }
      helper.offer_tools!(body, {}, 'ChatSpec', provider: 'openai', model: 'spec-model')
      expect(body).not_to have_key('tools')
      expect(body).not_to have_key('tool_choice')
    end
  end
end
