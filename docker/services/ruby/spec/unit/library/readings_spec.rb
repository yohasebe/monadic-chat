# frozen_string_literal: true

require_relative '../../spec_helper'
require 'securerandom'
require_relative '../../../lib/monadic/library/readings'
require_relative '../../../lib/monadic/history/serializer'
require_relative '../../../lib/monadic/utils/websocket'

RSpec.describe Monadic::Library::Readings do
  let(:request_id) { "q_#{SecureRandom.hex(8)}" }
  let(:first) { described_class.excerpt_id }
  let(:second) { described_class.excerpt_id }
  let(:reading) do
    { 'id' => described_class.reading_id, 'query' => 'notes',
      'excerpts' => [
        { 'id' => first, 'conversation_id' => 'conv-1', 'title' => 'Notes', 'source' => 'md', 'turn' => 1, 'text' => 'one' },
        { 'id' => second, 'conversation_id' => 'conv-1', 'title' => 'Notes', 'source' => 'md', 'turn' => 4, 'text' => 'two' }
      ] }
  end

  after { described_class.take(request_id) }

  it 'gives a reply its searches once, with the excerpts its text links to as cited' do
    described_class.add(request_id, 'chat-1', reading)
    other = reading.merge('id' => described_class.reading_id, 'query' => 'again')
    described_class.add(request_id, 'chat-1', other)

    records = described_class.seal(request_id, text: "As [Notes](#{described_class.link(second)}) says…")

    expect(records.map { |r| r['query'] }).to eq(%w[notes again])
    expect(records.first['cited']).to eq([second])
    expect(records.first['at']).to match(/\A\d{4}-\d\d-\d\dT/)
    expect(described_class.seal(request_id)).to eq([])
  end

  it 'marks no excerpt that the text does not link to by its id' do
    described_class.add(request_id, 'chat-1', reading)

    records = described_class.seal(request_id, text: 'As [Notes](mc:conv:conv-1) says, and one and two.')

    expect(records.first).not_to have_key('cited')
  end

  it 'takes nothing more once the reply ended' do
    described_class.take(request_id)

    expect(described_class.add(request_id, 'chat-1', reading)).to be false
  end

  it 'holds at most LIMIT searches for a reply' do
    described_class::LIMIT.times { described_class.add(request_id, 'chat-1', reading.merge('id' => described_class.reading_id)) }

    expect(described_class.add(request_id, 'chat-1', reading.merge('id' => described_class.reading_id))).to be false
  end

  it 'gives the records with the chat and session when the reply ends without its message' do
    session = { messages: [] }
    described_class.add(request_id, 'chat-1', reading, session: session)

    entry = described_class.take(request_id)

    expect(entry).to include(chat_id: 'chat-1', session: session)
    expect(entry[:records].size).to eq(1)
  end

  it 'records where the copy on the work screen is' do
    described_class.add(request_id, 'chat-1', reading)
    described_class.placed(request_id, reading['id'], 'conversations/c/workbench/library.md')

    expect(described_class.seal(request_id).first['path']).to eq('conversations/c/workbench/library.md')
  end

  describe 'with the chat' do
    let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
    let(:user) { { 'role' => 'user', 'text' => 'what do my notes say?', 'request_id' => request_id } }
    let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [user] } }

    it "puts the records on the user's message when the reply ends without one" do
      described_class.add(request_id, chat, reading, session: session)
      Class.new { include WebSocketHelper }.new.send(:library_readings_without_reply, request_id)

      expect(user[described_class::KEY].map { |r| r['query'] }).to eq(['notes'])
      expect(described_class.seal(request_id)).to eq([])
    end

    it 'puts nothing on a message of another chat' do
      described_class.add(request_id, chat, reading, session: session.merge(Monadic::Workspace::Chats::SESSION_KEY => 'other'))
      Class.new { include WebSocketHelper }.new.send(:library_readings_without_reply, request_id)

      expect(user).not_to have_key(described_class::KEY)
    end
  end

  it 'is kept by the history with its message' do
    kept = Monadic::History::Serializer.message({ 'role' => 'assistant', 'text' => 'done',
                                                  described_class::KEY => [reading, { 'id' => 'bad' }] })

    expect(kept[described_class::KEY].map { |r| r['id'] }).to eq([reading['id']])
  end

  it 'goes with its message into a shared (masked) export' do
    expect(WebSocketHelper::PRIVACY_EXPORT_MESSAGE_KEYS).to include(described_class::KEY)
  end

  describe '.clean' do
    it 'keeps the known keys of the right form' do
      dirty = reading.merge('cited' => [first, 'x_0000000000000000'], 'extra' => 'dropped', 'path' => '')
      dirty['excerpts'] = dirty['excerpts'] + [{ 'id' => 'not-an-id', 'text' => 'dropped' }]

      out = described_class.clean([dirty]).first

      expect(out.keys).to contain_exactly('id', 'query', 'excerpts', 'cited')
      expect(out['excerpts'].map { |e| e['id'] }).to eq([first, second])
      expect(out['cited']).to eq([first])
    end

    it 'cuts long text and refuses a record without its id' do
      long = reading.merge('query' => 'q' * 1000)
      long['excerpts'] = [long['excerpts'].first.merge('text' => 't' * 5000)]

      out = described_class.clean([long, { 'query' => 'no id' }])

      expect(out.size).to eq(1)
      expect(out.first['query'].length).to eq(described_class::QUERY_CHARS)
      expect(out.first['excerpts'].first['text'].length).to eq(described_class::TEXT_CHARS)
    end

    it 'gives nil when nothing is left' do
      expect(described_class.clean(nil)).to be_nil
      expect(described_class.clean([{ 'id' => 'bad' }])).to be_nil
    end
  end
end
