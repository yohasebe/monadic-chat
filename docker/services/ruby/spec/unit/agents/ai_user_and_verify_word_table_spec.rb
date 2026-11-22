# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/ai_user_agent'
require_relative '../../../lib/monadic/utils/websocket/verify_handler'
require_relative '../../../lib/monadic/utils/privacy/words'

# The suggestion of the AI User and the panel of Verify, asked in a chat that
# hides its words with a word table: what the other models are sent, and what
# their answers are put back with.
RSpec.describe 'The AI User and Verify in a chat with a word table' do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) do
    { parameters: {}, messages: [
      { 'role' => 'user', 'text' => 'Who was Ada Lovelace?', 'mid' => 'u1', 'app_name' => 'ChatOpenAI', 'active' => true },
      { 'role' => 'assistant', 'text' => 'Ada Lovelace wrote literal <<PERSON_1>>.', 'mid' => 'a1',
        'app_name' => 'ChatOpenAI', 'active' => true }
    ] }.tap { |s| Monadic::Workspace::Chats.start_new!(s) }
  end
  let(:table) { words.start!(session) }

  before { table.confirm!('Ada Lovelace', 'PERSON') }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  describe 'the AI User' do
    let(:agent) { Class.new { include AIUserAgent }.new }
    let(:sent) { [] }
    let(:app) { double('app', settings: { 'group' => 'OpenAI', 'display_name' => 'Chat' }) }

    before do
      stub_const('MonadicApp::AI_USER_INITIAL_PROMPT', 'You are simulating a user.')
      stub_const('CONFIG', CONFIG.merge('OPENAI_API_KEY' => 'test-not-sent'))
      stub_const('APPS', { 'ChatOpenAI' => app })
    end

    def suggest(reply)
      allow(app).to receive(:send_query) do |options, **|
        sent << options['messages'].first['content']
        reply.respond_to?(:call) ? reply.call : reply
      end
      agent.process_ai_user(session, { 'ai_user_provider' => 'openai' })
    end

    it 'sends the conversation with the words hidden, and puts the suggestion back' do
      result = suggest('Tell me more about <<PERSON_1>>.')
      expect(sent.join).to include('Who was <<PERSON_1>>?', '<<PERSON_1>> wrote literal ‹‹PERSON_1››.')
      expect(sent.join).not_to include('Ada Lovelace')
      expect(result).to include('type' => 'ai_user', 'content' => 'Tell me more about Ada Lovelace.')
    end

    it 'gives no suggestion once the words change while it is being sent' do
      result = suggest(lambda {
        table.confirm!('Grace Hopper', 'PERSON')
        words.check_sending!
        'late'
      })
      expect(result['type']).to eq('error')
    end

    it "sends nothing when the chat's table is not there" do
      words::LOCK.synchronize { words::TABLES.clear }
      result = suggest('x')
      expect(result['type']).to eq('error')
      expect(sent).to be_empty
    end
  end

  describe 'Verify' do
    let(:host) do
      Class.new do
        include WebSocketHelper
        attr_reader :out

        def send_to_client(_connection, payload)
          (@out ||= []) << payload
        end

        def send_or_broadcast(json, _sid = nil)
          (@out ||= []) << JSON.parse(json)
        end

        def sync_session_state!; end
      end.new
    end
    let(:asked) { [] }

    before do
      session[:messages] << { 'role' => 'user', 'text' => 'And her work?', 'mid' => 'u2', 'app_name' => 'ChatOpenAI', 'active' => true }
      session[:messages] << { 'role' => 'assistant', 'text' => 'Ada Lovelace wrote notes.', 'mid' => 'a2',
                              'app_name' => 'ChatOpenAI', 'active' => true }
      Thread.current[:rack_session] = session
      Thread.current[:websocket_session_id] = 'sid-1'
      stub_const('Monadic::MCP::Conduit', Module.new)
      allow(Thread).to receive(:new) { |&blk| blk.call && instance_double(Thread, join: nil) }
    end

    after do
      Thread.current[:rack_session] = nil
      Thread.current[:websocket_session_id] = nil
    end

    def verify(result)
      calls = asked
      Monadic::MCP::Conduit.define_singleton_method(:call) do |_name, arguments|
        calls << arguments
        result.respond_to?(:call) ? result.call : result
      end
      host.handle_ws_verify_confidence(nil, { 'mid' => 'a2' }, session)
      host.out.find { |m| m['type'] == 'verify_confidence' }
    end

    it 'sends the conversation with the words hidden, and puts what the panel says back' do
      shown = verify({ confidence: 'high', consensus: '<<PERSON_1>> wrote notes.', disagreements: ['not <<PERSON_1>>'],
                       responses: [{ provider: 'openai', text: '<<PERSON_1>> did.', success: true }] })
      sent = JSON.generate(asked)
      expect(sent).to include('Who was <<PERSON_1>>?', '<<PERSON_1>> wrote literal ‹‹PERSON_1››.', '<<PERSON_1>> wrote notes.')
      expect(sent).not_to include('Ada Lovelace')
      expect(shown).to include('consensus' => 'Ada Lovelace wrote notes.', 'disagreements' => ['not Ada Lovelace'])
      expect(shown['responses'].first['text']).to eq('Ada Lovelace did.')
      expect(session[:messages].last.dig('verify', :consensus)).to eq('Ada Lovelace wrote notes.')
    end

    it 'shows no verdict once the words change while it is being sent' do
      shown = verify(lambda {
        table.confirm!('Grace Hopper', 'PERSON')
        words.check_sending!
        { confidence: 'high' }
      })
      expect(shown).to include('confidence' => 'unavailable')
    end

    it "sends nothing when the chat's table is not there" do
      words::LOCK.synchronize { words::TABLES.clear }
      shown = verify({ confidence: 'high' })
      expect(asked).to be_empty
      expect(shown).to include('confidence' => 'unavailable')
    end
  end
end
