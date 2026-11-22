# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/workspace'
require_relative '../../../../lib/monadic/utils/websocket'

RSpec.describe 'The page asking about a chat word table' do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:backend) { instance_double(Monadic::Utils::Privacy::PresidioBackend, health: true) }
  let(:deps) { Monadic::Utils::ContainerDependencies }
  let(:session) do
    { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [], parameters: { 'conversation_language' => 'en' } }
  end
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= []
      end

      def send_to_client(_connection, payload)
        sent << payload
      end

      def sync_session_state!; end
    end.new
  end

  before { allow(Monadic::Utils::Privacy::PresidioBackend).to receive(:new).and_return(backend) }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  def token
    host.send(:chat_token, session)
  end

  def of_type(type)
    host.sent.select { |m| m['type'] == type }
  end

  def find(text = 'Ada met Ada and Bob.')
    host.send(:handle_ws_words_find, nil, session, { 'text' => text, 'request' => 7 })
    of_type('words_found').last
  end

  def change(**ops)
    host.send(:handle_ws_words_change, nil, session, { 'chat' => token, 'request' => 8 }.merge(ops.transform_keys(&:to_s)))
    of_type('words_changed').last
  end

  def entity(word, type = 'PERSON')
    { 'original' => word, 'type' => type }
  end

  describe 'finding words' do
    it 'gives each word found once, and changes nothing of the chat' do
      allow(backend).to receive(:anonymize).and_return(entities: [entity('Ada'), entity('Ada', 'LOCATION'), entity('Bob')])

      reply = find

      expect(reply['candidates']).to eq([{ 'word' => 'Ada', 'type' => 'PERSON' }, { 'word' => 'Bob', 'type' => 'PERSON' }])
      expect(reply).to include('request' => 7, 'chat' => token)
      expect(words.marked?(session)).to be(false)
    end

    it 'leaves out words already decided about and those no table could take' do
      table = words.start!(session)
      table.confirm!('Ada', 'PERSON')
      table.keep!('Bob')
      allow(backend).to receive(:anonymize)
        .and_return(entities: [entity('Ada'), entity('Bob'), entity("two\nlines"), entity('Cy', 'lower'), entity('Dee')])

      expect(find['candidates'].map { |c| c['word'] }).to eq(['Dee'])
    end

    it 'looks in the language chosen for the chat, among those installed' do
      allow(Monadic::Utils::Privacy::LanguageDetector).to receive(:installed_languages).and_return(%w[en ja])
      session[:parameters]['conversation_language'] = 'ja'
      allow(backend).to receive(:anonymize).and_return(entities: [])

      find

      expect(backend).to have_received(:anonymize).with(hash_including(languages: ['ja']))
    end

    it 'starts the container that finds them when it is not up, and says so' do
      allow(backend).to receive(:health).and_return(false)
      allow(host).to receive(:privacy_container_coming_up?).and_return(false)
      allow(deps).to receive(:start_service_async)

      expect(find['error']).to eq('privacy_container_starting')
      expect(deps).to have_received(:start_service_async).with(:privacy, anything)
    end

    it 'does not start it when the user turned it off, and says it is not available' do
      allow(backend).to receive(:health).and_return(false)
      allow(host).to receive(:privacy_container_coming_up?).and_return(false)
      allow(deps).to receive(:start_service_async)
      stub_const('CONFIG', { 'PRIVACY_FILTER' => 'false' })

      expect(find['error']).to eq('privacy_container_unreachable')
      expect(deps).not_to have_received(:start_service_async)
    end

    it 'does not start it twice' do
      allow(backend).to receive(:health).and_return(false)
      allow(host).to receive(:privacy_container_coming_up?).and_return(true)
      allow(deps).to receive(:start_service_async)

      expect(find['error']).to eq('privacy_container_starting')
      expect(deps).not_to have_received(:start_service_async)
    end

    it 'says it could not find them, without the text' do
      allow(backend).to receive(:anonymize).and_raise(StandardError, 'Ada failed')

      reply = find

      expect(reply['error']).to eq('words_find_failed')
      expect(reply.to_s).not_to include('Ada')
    end

    it 'refuses a text too long to look through' do
      expect(backend).not_to receive(:anonymize)

      expect(find('x' * (WebSocketHelper::WORDS_FIND_MAX_CHARS + 1))['error']).to eq('words_text_too_long')
    end

    it 'refuses for a chat whose table is lost' do
      session[words::MARK_KEY] = session[:chat_id]

      expect(find['error']).to eq('words_refused')
    end
  end

  describe 'deciding about words' do
    it 'hides the words given from now on, saves the chat and shows the table' do
      expect(host).to receive(:sync_session_state!)

      expect(change(hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }])).to include('success' => true, 'request' => 8)

      expect(words.active_of(session)).to eq(['Ada'])
      expect(of_type('word_table').last).to include('chat' => token, 'marked' => true,
                                                    'active' => [{ 'word' => 'Ada', 'type' => 'PERSON', 'placeholder' => '<<PERSON_1>>' }], 'kept' => [])
    end

    it 'takes a word off and does not offer it again, and can put it back' do
      change(hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }])

      change(keep: ['Ada'])
      expect(words.active_of(session)).to be_empty
      expect(of_type('word_table').last['kept']).to eq(['Ada'])

      change(show: ['Ada'])
      expect(of_type('word_table').last['kept']).to be_empty
    end

    it 'changes the type a word is shown with, keeping its placeholder' do
      change(hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }])
      before = words.table(session).apply('Ada')

      change(hide: [{ 'word' => 'Ada', 'type' => 'ORGANIZATION' }])

      expect(words.table(session).apply('Ada')).to eq(before)
      expect(of_type('word_table').last['active']).to eq([{ 'word' => 'Ada', 'type' => 'ORGANIZATION', 'placeholder' => before }])
    end

    it 'takes nothing meant for another chat' do
      expect(host).not_to receive(:sync_session_state!)

      reply = change(chat: 'another', hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }])

      expect(reply).to include('success' => false, 'error' => 'words_other_chat')
      expect(words.marked?(session)).to be(false)
    end

    it 'does not begin a table for a change that cannot be made' do
      reply = change(hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }, { 'word' => "two\nlines", 'type' => 'PERSON' }])

      expect(reply).to include('success' => false, 'error' => 'words_refused')
      expect(words.marked?(session)).to be(false)
    end

    it 'does not begin a table when nothing is asked' do
      expect(change).to include('success' => true)

      expect(words.marked?(session)).to be(false)
    end

    it 'ends a Live Conversation when the chat begins to hide its words' do
      session[:_sts] = Object.new
      allow(host).to receive(:teardown_sts_session)

      change(hide: [{ 'word' => 'Ada', 'type' => 'PERSON' }])

      expect(host).to have_received(:teardown_sts_session).with(session)
      expect(of_type('sts_session').last).to include('state' => 'stopped')
      expect(of_type('error').last['content']).to include('hides its words')
    end
  end

  it 'tells the page the table of the chat it is in' do
    words.start!(session).confirm!('Ada', 'PERSON')

    host.send(:send_word_table, nil, session)

    expect(of_type('word_table').last).to include('chat' => token, 'marked' => true)
  end

  it 'says a table is not available rather than none' do
    session[words::MARK_KEY] = session[:chat_id]

    host.send(:send_word_table, nil, session)

    expect(of_type('word_table').last).to include('marked' => true, 'unavailable' => true)
  end
end
