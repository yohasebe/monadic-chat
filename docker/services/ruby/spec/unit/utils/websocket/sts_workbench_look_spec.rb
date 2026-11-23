# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/monadic/utils/websocket'

# A live voice session can look at the work screen (look_at_workbench) as a
# typed reply can: for the tab the session runs in, every provider getting
# the text, and a provider that takes images (OpenAI) the image too, added
# after the tool's result as a message of the user's.
RSpec.describe 'Looking at the work screen in a Live Conversation' do
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat_id, _ws_generation: 3, parameters: {}, messages: [] } }
  let(:helper) { WebSocketHelper }
  let(:image) { double('image', data_url: 'data:image/png;base64,UElD') }
  let(:asked) { [] }

  before do
    allow(Monadic::Workbench::Look).to receive(:run) do |caller, scope:, images:|
      asked << { caller: caller, scope: scope, images: images }
      Monadic::Workbench::Look::Result.new(observation_id: 'look_1', text: '{"status":"looked"}')
    end
    observation = double('observation', image: images_given ? image : nil, caption: 'The image below is what look_at_workbench looked at')
    ledger = double('ledger', observations: [observation])
    allow(ledger).to receive(:close!)
    allow(Monadic::Workbench::Look::Ledger).to receive(:of_request).and_return(ledger)
  end

  let(:images_given) { true }

  it 'looks for the tab the session runs in, in its chat, as a request of its own' do
    helper.sts_look_at_workbench({ 'scope' => 'whole' }, session, tab: 'tab-9', provider: 'openai')
    caller = asked.last[:caller]
    expect(caller.chat_id).to eq(chat_id)
    expect(caller.tab).to eq('tab-9')
    expect(caller.generation).to eq(3)
    expect(caller.epoch).to eq(Monadic::Workspace::Chats.epoch(chat_id))
    expect(Monadic::Workspace::Ids.valid?(:request, caller.request_id)).to be(true)
    expect(asked.last[:scope]).to eq('whole')
  end

  it 'gives OpenAI the text and the image' do
    out = helper.sts_look_at_workbench({}, session, tab: 'tab-9', provider: 'openai')
    expect(asked.last[:images]).to be(true)
    expect(out).to eq(output: '{"status":"looked"}',
                      image: { data_url: 'data:image/png;base64,UElD', caption: 'The image below is what look_at_workbench looked at' })
  end

  context 'for a provider that takes no images' do
    let(:images_given) { false }

    it 'asks for no image and gives the text only' do
      %w[xai gemini].each do |provider|
        out = helper.sts_look_at_workbench({}, session, tab: 'tab-9', provider: provider)
        expect(asked.last[:images]).to be(false)
        expect(out).to eq(output: '{"status":"looked"}', image: nil)
      end
    end
  end

  it 'passes a refusal on as it is' do
    allow(Monadic::Workbench::Look).to receive(:run).and_return('❌ Nothing was looked at in the work screen (no_selection): nothing.')
    expect(helper.sts_look_at_workbench({}, session, tab: 'tab-9', provider: 'openai')).to start_with('❌ Nothing was looked at')
  end

  describe 'the call and its result' do
    let(:host) do
      sess = session
      Class.new do
        include WebSocketHelper

        define_method(:session) { sess }
        def send_or_broadcast(*); end
      end.new
    end
    let(:conn) do
      Class.new do
        attr_reader :writes

        def initialize = @writes = []
        def write(body) = @writes << JSON.parse(body)
        def flush; end
      end.new
    end

    it 'runs the look with the tab and the provider, and keeps the image with the result' do
      state = { offered_tool_names: ['look_at_workbench'], provider: 'openai' }
      done = host.send(:sts_execute_tool_safely, { name: 'look_at_workbench', parsed_arguments: {} }, state, 'tab-9', session)
      expect(asked.last[:caller].tab).to eq('tab-9')
      expect(done[:image][:data_url]).to eq('data:image/png;base64,UElD')
    end

    it 'sends OpenAI the result, then the image as a message of the user, then asks for the reply' do
      state = { provider: 'openai', pending_tool_calls: { 'r1' => { 'c1' => true } } }
      host.send(:sts_send_tool_result, conn, state,
                { rid: 'r1', call_id: 'c1', name: 'look_at_workbench', output: '{"status":"looked"}',
                  image: { data_url: 'data:image/png;base64,UElD', caption: 'The image below' } }, 'tab-9')
      expect(conn.writes.map { |w| w['type'] }).to eq(['conversation.item.create', 'conversation.item.create', 'response.create'])
      expect(conn.writes[0].dig('item', 'type')).to eq('function_call_output')
      expect(conn.writes[1]['item']).to include('type' => 'message', 'role' => 'user')
      expect(conn.writes[1].dig('item', 'content')).to eq([{ 'type' => 'input_text', 'text' => 'The image below' },
                                                           { 'type' => 'input_image', 'image_url' => 'data:image/png;base64,UElD' }])
    end

    it 'sends a result with no image as before' do
      state = { provider: 'openai', pending_tool_calls: { 'r1' => { 'c1' => true } } }
      host.send(:sts_send_tool_result, conn, state, { rid: 'r1', call_id: 'c1', name: 'get_current_time', output: 'now' }, 'tab-9')
      expect(conn.writes.map { |w| w['type'] }).to eq(['conversation.item.create', 'response.create'])
    end
  end
end
