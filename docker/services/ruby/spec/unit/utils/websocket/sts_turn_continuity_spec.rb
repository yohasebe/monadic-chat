# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/monadic/utils/websocket'

# One utterance, one turn: an utterance a turn detection committed in two
# items stays one turn with one user message, and the answer after a tool
# call is the turn's that called it, so that the page plays it after the
# words before it, not over them.
RSpec.describe 'A Live Conversation turn across items and tool calls' do
  let(:host) do
    Class.new do
      include WebSocketHelper

      def session = (@session ||= { parameters: {}, messages: [] })
      def sent = (@sent ||= [])
      def send_or_broadcast(payload, _id) = sent << JSON.parse(payload)
      def sync_session_state!; end
    end.new
  end

  def turn_with_card(id, item_id, text)
    msg = { 'mid' => 'm1', 'role' => 'user', 'text' => text }
    { id: id, item_id: item_id, user_msg_ref: msg, user_partial: +'', pending_fragments: [] }
  end

  it 'keeps the later items of an utterance in its turn\'s user message, each once' do
    turn = turn_with_card('B', 'item_1', 'Please read')
    state = { turn: turn, items: { 'item_1' => turn, 'item_2' => turn } }
    host.send(:sts_handle_transcription_completed, state, { 'item_id' => 'item_2', 'transcript' => 'the marked line.' }, 'tab')
    expect(state[:turn]).to equal(turn)
    expect(turn[:user_msg_ref]['text']).to eq('Please read the marked line.')
    # The same item again, grown (a provider that sends it more than once).
    host.send(:sts_handle_transcription_completed, state, { 'item_id' => 'item_2', 'transcript' => 'the marked line, please.' }, 'tab')
    expect(turn[:user_msg_ref]['text']).to eq('Please read the marked line, please.')
    expect(host.sent.last).to include('type' => 'stt', 'content' => 'Please read the marked line, please.')
  end

  it 'still opens a turn of its own for an item no turn took' do
    turn = turn_with_card('B', 'item_1', 'Please read')
    state = { turn: turn, items: { 'item_1' => turn } }
    allow(host).to receive(:sts_start_new_turn).and_call_original
    host.send(:sts_handle_transcription_completed, state, { 'item_id' => 'item_9', 'transcript' => 'Something else.' }, 'tab')
    expect(host).to have_received(:sts_start_new_turn)
    expect(turn[:user_msg_ref]['text']).to eq('Please read')
  end

  it "binds a tool call to the turn of the response that made it, and asks for the answer after it in that turn" do
    asked = { id: 'B' }
    later = { id: 'C' }
    queue = []
    def queue.enqueue(cmd) = push(cmd)
    state = { tools_enabled: true, cmd_queue: queue, turn: later, responses: { 'resp_1' => asked } }
    host.send(:sts_handle_tool_call_detected, state, { 'response_id' => 'resp_1', 'call_id' => 'c1', 'name' => 'get_current_time',
                                                       'arguments' => '{}' }, 'tab')
    expect(state[:tool_batch_turns]['resp_1']).to equal(asked)

    conn = Class.new do
      def writes = (@writes ||= [])
      def write(body) = writes << JSON.parse(body)
      def flush; end
    end.new
    host.send(:sts_create_tool_continuation, conn, state, asked)
    expect(conn.writes).to eq([{ 'type' => 'response.create' }])
    expect(state[:pending_response_turn]).to equal(asked)
    expect(state[:tool_continuation_turn]).to equal(asked)
  end
end
