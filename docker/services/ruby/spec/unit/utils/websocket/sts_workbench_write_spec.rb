# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/monadic/utils/websocket'

# In a Live Conversation the AI can write on the work screen (write_section,
# put_on_workbench). What a turn's tools make there is recorded under one
# request of the turn, run as a reply is, and kept by the turn's card, so
# that deleting the turn takes it away; a turn that ends with no card puts
# it in the trash, as a stopped reply does.
RSpec.describe 'Writing on the work screen in a Live Conversation' do
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat_id, _ws_generation: 2, parameters: { 'app_name' => 'LiveConversationOpenAI' }, messages: [] } }
  let(:host) do
    sess = session
    Class.new do
      include WebSocketHelper

      define_method(:session) { sess }
      def sent = (@sent ||= [])
      def send_or_broadcast(payload, _id) = sent << JSON.parse(payload)
      def get_session_params = session[:parameters]
      def detect_language(_text) = 'en'
      def sync_session_state!; end
    end.new
  end
  let(:workbench) { Monadic::Workbench }

  after do
    WebSocketHelper::Replies.reset!
    workbench::Made.reset!
    workbench::Shown.reset!
  end

  def record_for(request_id)
    path = "conversations/c_x/runs/#{request_id}"
    workbench::Made.add(request_id, path, chat_id: chat_id)
    workbench::Shown.add(request_id, { 'file' => { 'path' => "#{path}/plan.md", 'name' => 'plan.md', 'sha256' => 'a' * 64,
                                                   'preview' => 'text' } })
    path
  end

  describe "a turn's request" do
    it 'is opened as a running reply the first time a tool makes something, and is the same for the turn' do
      turn = {}
      first = host.send(:sts_turn_request!, turn, 'tab-1')
      expect(Monadic::Workspace::Ids.valid?(:request, first)).to be(true)
      expect(host.send(:sts_turn_request!, turn, 'tab-1')).to eq(first)
      handle = WebSocketHelper::Replies.find(first)
      expect(handle.phase).to eq(:running)
      expect([handle.chat_id, handle.tab, handle.generation]).to eq([chat_id, 'tab-1', 2])
      expect(workbench::Shown.running?(first)).to be(true)
    end

    it 'is none in a session in no chat' do
      session.delete(Monadic::Workspace::Chats::SESSION_KEY)
      expect(host.send(:sts_turn_request!, {}, 'tab-1')).to be_nil
    end

    it "is given to a tool that makes something, not to a look" do
      queued = []
      queue = Object.new.tap { |q| q.define_singleton_method(:enqueue) { |cmd| queued << cmd } }
      state = { tools_enabled: false, cmd_queue: queue, turn: {} }
      %w[write_section look_at_workbench].each_with_index do |name, i|
        host.send(:sts_handle_tool_call_detected, state, { 'response_id' => 'r1', 'call_id' => "c#{i}", 'name' => name,
                                                           'arguments' => '{}' }, 'tab-1')
      end
      write, look = queued.map(&:last)
      expect(Monadic::Workspace::Ids.valid?(:request, write[:request_id])).to be(true)
      expect(write[:request_id]).to eq(state[:turn][:request_id])
      expect(look[:request_id]).to be_nil
    end
  end

  describe 'a writing tool' do
    let(:state) { { offered_tool_names: %w[write_section put_on_workbench], provider: 'openai' } }

    it 'writes for the turn: its caller is the session, the tab and the turn\'s request' do
      got = nil
      allow_any_instance_of(MonadicSharedTools::WorkbenchTools).to receive(:write_section) do |_host, **args|
        got = args
        '{"status":"shown_in_work_screen"}'
      end
      out = host.send(:sts_execute_tool_safely, { name: 'write_section', request_id: 'q_turn1',
                                                  parsed_arguments: { 'document' => 'Plan', 'section' => 'list', 'content' => '- a' } },
                      state, 'tab-1', session)
      expect(out).to eq('{"status":"shown_in_work_screen"}')
      expect(got).to include(document: 'Plan', section: 'list', content: '- a', session: session)
      expect([got[:workbench].chat_id, got[:workbench].tab, got[:workbench].request_id]).to eq([chat_id, 'tab-1', 'q_turn1'])
    end

    it 'is not run without a request of the turn' do
      expect_any_instance_of(MonadicSharedTools::WorkbenchTools).not_to receive(:put_on_workbench)
      out = host.send(:sts_execute_tool_safely, { name: 'put_on_workbench', parsed_arguments: { 'name' => 'a.md', 'content' => 'x' } },
                      state, 'tab-1', session)
      expect(out).to start_with('❌ `put_on_workbench` was not run')
    end
  end

  describe "the turn's card" do
    it 'keeps what the turn made and showed, and the turn\'s request ends' do
      turn = { id: 't1' }
      request_id = host.send(:sts_turn_request!, turn, 'tab-1')
      path = record_for(request_id)
      host.send(:sts_send_assistant_card, {}, turn, 'Added it to the list.', 'tab-1', interrupted: false)
      message = session[:messages].last
      expect(message['workbench_made']).to eq([path])
      expect(message['workbench_shown'].map { |e| e['path'] }).to eq(["#{path}/plan.md"])
      expect(host.sent.last.dig('content', 'workbench_made')).to eq([path])
      expect(turn).not_to have_key(:request_id)
      expect(WebSocketHelper::Replies.find(request_id)).to be_nil
    end

    it "adds what a continuation made after it to the same message" do
      turn = { id: 't1' }
      first = record_for(host.send(:sts_turn_request!, turn, 'tab-1'))
      host.send(:sts_send_assistant_card, {}, turn, 'One moment.', 'tab-1', interrupted: false)
      second = record_for(host.send(:sts_turn_request!, turn, 'tab-1'))
      host.send(:sts_fold_tool_continuation, {}, turn, { 'transcript' => 'Done.' }, 'tab-1')
      expect(session[:messages].last['workbench_made']).to eq([first, second])
      expect(host.sent.last).to include('type' => 'sts_card_text')
      expect(host.sent.last['workbench_shown'].size).to eq(2)
    end

    it 'puts in the trash what a turn made when no card takes it' do
      turn = { id: 't1', assistant_transcript: +'', pending_fragments: [] }
      request_id = host.send(:sts_turn_request!, turn, 'tab-1')
      record_for(request_id)
      expect(workbench::Made).to receive(:close).with(request_id).and_call_original
      host.send(:sts_finalize_interrupted_turn, {}, turn, 'tab-1')
      expect(WebSocketHelper::Replies.find(request_id)).to be_nil
      expect(session[:messages]).to be_empty
    end

    it 'puts in the trash what the turn going on made when the session ends' do
      turn = {}
      request_id = host.send(:sts_turn_request!, turn, 'tab-1')
      session[:_sts] = { turn: turn }
      expect(workbench::Made).to receive(:close).with(request_id)
      WebSocketHelper.teardown_sts_session_for(session)
      expect(WebSocketHelper::Replies.find(request_id)).to be_nil
    end
  end
end
