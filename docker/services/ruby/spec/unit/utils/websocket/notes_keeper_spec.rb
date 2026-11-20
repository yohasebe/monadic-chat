# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/monadic/utils/websocket/notes_keeper'

# The notes added after a reply (WebSocketHelper#keep_notes_for): what is
# sent, and when what comes back is given to the reply.
RSpec.describe 'Notes added after the reply' do
  let(:keeper) { Monadic::TurnState::Keeper }
  let(:state_key) { Monadic::TurnState::Form::STATE_CHANGES_KEY }
  let(:app_name) { 'ChatOpenAI' }
  let(:notes_now) { { 'topics' => [], 'people' => [], 'notes' => [] } }
  let(:live) { { 'tab-1' => 1 } }

  let(:app) do
    Class.new do
      attr_reader :bodies
      attr_accessor :answer, :during, :settings

      def initialize
        @bodies = []
        @settings = { provider: 'openai' }
        @answer = '{"add": {"topics": ["Linguistics"]}}'
      end

      def send_query(body, model:)
        @bodies << [body, model]
        @during&.call
        @answer
      end
    end.new
  end

  let(:helper) do
    Class.new do
      include WebSocketHelper
      attr_reader :synced

      def initialize
        @synced = 0
      end

      def sync_session_state!
        @synced += 1
      end

      public :keep_notes_for
    end.new
  end

  let(:user) { { 'mid' => 'u1', 'role' => 'user', 'text' => 'I teach linguistics.', 'request_id' => 'r1' } }
  let(:reply) { { 'mid' => 'a1', 'role' => 'assistant', 'text' => 'Nice!', 'app_name' => app_name } }
  let(:session) do
    # The model chosen now differs from the one the request was sent with.
    s = { parameters: { 'app_name' => app_name, 'model' => 'chosen-later' }, _ws_generation: 1,
          messages: [user.dup, reply.dup] }
    Monadic::Workspace::Chats.start_new!(s)
    s
  end
  let(:job) do
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    keeper::Job.new(session: session, chat_id: chat_id, epoch: Monadic::Workspace::Chats.epoch(chat_id), tab: 'tab-1',
                    generation: 1, app_name: app_name, model: 'spec-model', user_mid: 'u1', reply_mid: 'a1',
                    user_text: user['text'], reply_text: reply['text'], source: keeper.source_of(user, reply),
                    voids: keeper.voids(chat_id))
  end

  before do
    stub_const('APPS', { app_name => app })
    allow(Monadic::TurnState::Notes).to receive(:refresh)
    allow(Monadic::TurnState).to receive(:items) { |_session, field| notes_now[field].map { |text| { data: text } } }
    allow(WebSocketHelper).to receive(:live_generation) { |tab| live[tab] }
  end

  def reply_now
    session[:messages].find { |m| m['mid'] == 'a1' }
  end

  def run
    helper.keep_notes_for(session, job)
  end

  it 'asks the reply\'s own app with the model its request was sent with, and gives the new items to the reply' do
    expect(Monadic::TurnState).not_to receive(:changed!)
    expect(Monadic::TurnState).to receive(:refresh!).with(job.chat_id)
    run
    body, model = app.bodies.first
    expect(model).to eq('spec-model')
    expect(body['model']).to eq('spec-model')
    expect(body).not_to have_key('tools')
    expect(Array(reply_now[state_key]).map { |c| [c['collection'], c['op'], c['data'], c['app']] })
      .to eq([['topics', 'set', 'Linguistics', app_name]])
    expect(helper.synced).to eq(1)
    expect(Monadic::TurnState::Notes).to have_received(:refresh).with(session, show: :quiet, tab: 'tab-1')
  end

  it 'sends the exchange only, never the notes' do
    notes_now['notes'] = ['A private fact']
    run
    sent = JSON.generate(app.bodies.first.first)
    expect(sent).not_to include('A private fact')
  end

  it 'asks nothing for an exchange deleted or edited while it waited, and nothing after notes were removed' do
    session[:messages].delete_at(1)
    run
    expect(app.bodies).to be_empty

    session[:messages] << reply.dup
    allow(keeper).to receive(:keeping?).and_return(true)
    keeper.removing!(session)
    run
    expect(app.bodies).to be_empty
  end

  it 'gives nothing when notes were removed while it was asked' do
    allow(keeper).to receive(:keeping?).and_return(true)
    app.during = -> { keeper.removing!(session) }
    run
    expect(reply_now).not_to have_key(state_key)
  end

  it 'sends the reply as the model wrote it, not as the page shows it' do
    job.reply_text = 'Nice!'
    reply_now['text'] = 'Nice!<div class="citations">…</div>'
    job.source = keeper.source_of(user, reply_now)
    run
    expect(JSON.parse(app.bodies.first.first['messages'].last['content'])['assistant']).to eq('Nice!')
  end

  it 'logs neither what is sent nor what comes back' do
    seen = []
    allow(Monadic::Utils::ExtraLogger).to receive(:log) { |&block| seen << block&.call }
    app.during = -> { expect(Monadic::Utils::ContentFreeLogging.active?).to be(true) }
    app.answer = 'not json: SECRET-ANSWER'
    run
    expect(seen.compact.join).not_to include('SECRET-ANSWER')
    expect(seen.compact.join).not_to include('linguistics')
  end

  it 'keeps what the reply changed before, with what comes now' do
    reply_now[state_key] = Monadic::TurnState::Form.clean_changes(
      [{ 'kind' => 'item', 'collection' => 'notes', 'id' => 'x1', 'op' => 'remove', 'app' => app_name }]
    )
    run
    expect(reply_now[state_key].map { |c| c['op'] }).to eq(%w[remove set])
  end

  it 'writes nothing when nothing is to be added, or it came to the notes meanwhile' do
    app.answer = '{"add": {}}'
    run
    expect(reply_now).not_to have_key(state_key)
    expect(helper.synced).to eq(0)

    app.answer = '{"add": {"topics": ["Linguistics"]}}'
    app.during = -> { notes_now['topics'] = ['Linguistics'] }
    run
    expect(reply_now).not_to have_key(state_key)
  end

  it 'gives nothing to an exchange edited while it was asked' do
    app.during = -> { reply_now['text'] = 'Edited.' }
    run
    expect(reply_now).not_to have_key(state_key)

    app.during = -> { session[:messages][0]['text'] = 'Edited too.' }
    reply_now['text'] = 'Nice!'
    run
    expect(reply_now).not_to have_key(state_key)
  end

  it 'gives the items to the same reply when a message came before it meanwhile' do
    app.during = -> { session[:messages].unshift({ 'mid' => 'x', 'role' => 'user', 'text' => 'x' }) }
    run
    expect(reply_now[state_key].map { |c| c['data'] }).to eq(['Linguistics'])
  end

  it 'sends and gives nothing once the chat was reset, the app changed, or another connection took the tab' do
    live['tab-1'] = 2
    run
    expect(app.bodies).to be_empty

    live['tab-1'] = 1
    app.during = -> { live['tab-1'] = nil }
    run
    expect(reply_now).not_to have_key(state_key)

    live['tab-1'] = 1
    app.during = -> { session[:parameters]['app_name'] = 'ChatClaude' }
    run
    expect(reply_now).not_to have_key(state_key)

    session[:parameters]['app_name'] = app_name
    app.during = -> { Monadic::Workspace::Chats.start_new!(session) }
    run
    expect(reply_now).not_to have_key(state_key)
  end

  it 'gives nothing for an error, an answer that is not JSON, or a change too large for the chat' do
    allow(Monadic::Utils::ErrorFormatter).to receive(:error_reply?).and_return(true)
    run
    allow(Monadic::Utils::ErrorFormatter).to receive(:error_reply?).and_return(false)
    app.answer = 'I could not decide.'
    run
    app.answer = '{"add": {"topics": ["Linguistics"]}}'
    stub_const('Monadic::TurnState::Form::CHAT_BYTES', 10)
    run
    expect(reply_now).not_to have_key(state_key)
    expect(helper.synced).to eq(0)
  end

  it 'asks nothing of an Ollama model without the tools capability' do
    app.settings = { provider: 'ollama' }
    stub_const('OllamaHelper', Class.new { def self.fetch_model_capabilities(_model) = { capabilities: ['completion'] } })
    run
    expect(app.bodies).to be_empty
  end

  context 'in a chat that hides words' do
    let(:words) { Monadic::Utils::Privacy::Words }

    before do
      words.start!(session).confirm_all!([['Taro Yamada', 'PERSON']])
      job.user_text = 'My colleague Taro Yamada teaches linguistics.'
      job.reply_text = 'Taro Yamada sounds great.'
    end

    after { words::LOCK.synchronize { words::TABLES.clear } }

    %w[ChatOpenAI ChatClaude ChatGemini ChatGrok ChatMistral ChatCohere ChatDeepSeek ChatOllama].each do |name|
      it "sends the user's text and the reply with the words hidden (#{name})" do
        stub_const('APPS', { name => app })
        session[:parameters]['app_name'] = name
        job.app_name = name
        allow(helper).to receive(:notes_model_ok?).and_return(true)
        run
        sent = JSON.generate(app.bodies.first.first)
        expect(sent).not_to include('Taro Yamada')
        expect(sent).to match(/<<PERSON_\d+>>/)
      end
    end

    it 'gives nothing when the words change while it is asked' do
      app.during = -> { words.table(session).confirm_all!([['linguistics', 'TOPIC']]) }
      run
      expect(reply_now).not_to have_key(state_key)
    end
  end
end
