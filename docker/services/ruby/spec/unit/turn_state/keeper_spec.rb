# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/turn_state/keeper'
require_relative '../../../lib/monadic/turn_state/notes'

RSpec.describe Monadic::TurnState::Keeper do
  let(:keeper) { described_class }
  let(:notes) { { 'topics' => ['Linguistics'], 'people' => ['Sato - teacher'], 'notes' => ['Sleeps badly'] } }

  after do
    described_class::LOCK.synchronize do
      [described_class::JOBS, described_class::WORKERS, described_class::SENT, described_class::VOIDS,
       described_class::REMOVING].each(&:clear)
    end
  end

  describe 'reading what comes back' do
    it 'takes an object with "add", bare or in a code fence' do
      expect(keeper.parse('{"add": {}}')).to eq('add' => {})
      expect(keeper.parse("```json\n{\"add\": {}}\n```")).to eq('add' => {})
    end

    it 'refuses what is not such an object' do
      expect { keeper.parse('no notes') }.to raise_error(described_class::Invalid)
      expect { keeper.parse('{"add": ') }.to raise_error(described_class::Invalid)
      expect { keeper.parse('[1, 2]') }.to raise_error(described_class::Invalid)
      expect { keeper.parse('{"remove": []}') }.to raise_error(described_class::Invalid)
    end
  end

  describe 'the items to add' do
    it 'adds new short items once, and nothing the notes hold as stored or as sent' do
      shown = { 'people' => ['<<PERSON_1>> - teacher'] }
      list = keeper.additions({ 'add' => { 'topics' => ['Linguistics', 'Corpus', 'Corpus', '', 'x' * 300],
                                           'people' => ['<<PERSON_1>> - teacher'], 'notes' => [42] } }, notes, shown)
      expect(list.map { |c| [c['collection'], c['op'], c['data']] }).to eq([['topics', 'set', 'Corpus']])
      expect(list.first['id']).to eq(Monadic::TurnState.text_id('Corpus'))
    end

    it 'adds at most a few items to a field' do
      list = keeper.additions({ 'add' => { 'notes' => (1..30).map { |n| "fact #{n}" } } }, notes)
      expect(list.size).to eq(described_class::ITEMS_PER_FIELD)
    end

    it 'never removes anything' do
      list = keeper.additions({ 'add' => {}, 'remove' => [{ 'ref' => 'n1' }], 'clear' => { 'quote' => 'x' } }, notes)
      expect(list).to eq([])
    end

    it 'refuses a malformed batch as a whole' do
      expect { keeper.additions({ 'add' => [] }, notes) }.to raise_error(described_class::Invalid)
      expect { keeper.additions({ 'add' => { 'topics' => 'one' } }, notes) }.to raise_error(described_class::Invalid)
    end
  end

  describe 'the request' do
    it 'asks with no tools, a small output and the least reasoning, with only the exchange as data' do
      body = keeper.request_body('spec-model', 'u', 'a')
      expect(body).not_to have_key('tools')
      expect(body['max_tokens']).to eq(described_class::OUTPUT_TOKENS)
      expect(body['messages'].first['content']).to eq(described_class::INSTRUCTIONS)
      expect(JSON.parse(body['messages'].last['content'])).to eq('user' => 'u', 'assistant' => 'a')
    end

    it 'keeps the beginning and the end of a long text' do
      text = "#{'a' * 5_000}the end"
      expect(keeper.cut(text).length).to be < text.length
      expect(keeper.cut(text)).to end_with('the end')
    end
  end

  describe 'what a job is bound to' do
    it 'keeps the model and the user\'s text a request was sent with, for its reply only' do
      keeper.sent_with('r1', 'model-a', 'hello')
      expect(keeper.sent('r1')).to eq(model: 'model-a', text: 'hello')
      expect(keeper.sent('r1')).to be_nil
      expect(keeper.sent('r2')).to be_nil
    end

    it 'lets go of the chat\'s waiting additions when a reply removes notes, and that reply adds none' do
      session = { Monadic::Workspace::Chats::SESSION_KEY => 'c_rm' }
      allow(keeper).to receive(:keeping?).and_return(true)
      allow(Monadic::Workbench::Caller).to receive(:current).and_return(double(request_id: 'r9'))
      keeper.enqueue(described_class::Job.new(chat_id: 'c_rm'))
      before = keeper.voids('c_rm')
      keeper.removing!(session)
      expect(keeper.next_job('c_rm')).to be_nil
      expect(keeper.voids('c_rm')).to eq(before + 1)
      expect(keeper.removed_in?('r9')).to be(true)
      expect(keeper.removed_in?('r9')).to be(false)
    end

    it 'tells the exchange apart once either message changed' do
      user = { 'mid' => 'u1', 'text' => 'hi' }
      reply = { 'mid' => 'a1', 'text' => 'hello' }
      source = keeper.source_of(user, reply)
      expect(keeper.source_of(user.merge('text' => 'edited'), reply)).not_to eq(source)
      expect(keeper.source_of(user, reply.merge('text' => 'edited'))).not_to eq(source)
      expect(keeper.source_of(nil, reply)).not_to eq(source)
    end
  end

  describe 'the worker of a chat' do
    def job(chat_id)
      described_class::Job.new(chat_id: chat_id)
    end

    it 'takes the chat\'s jobs in order, one worker at a time, and says when it starts and ends' do
      calls = []
      taken = []
      gate = Queue.new
      keeper.enqueue(job('c_spec'))
      first = keeper.start('c_spec', on_change: -> { calls << :changed }) do
        gate.pop if taken.empty?
        while (j = keeper.next_job('c_spec'))
          taken << j
        end
      end
      expect(keeper.status('c_spec')).to eq('updating')
      keeper.enqueue(job('c_spec'))
      expect(keeper.start('c_spec') { raise 'not run' }).to be_nil
      gate << :go
      first.join
      expect(taken.size).to eq(2)
      expect(keeper.status('c_spec')).to be_nil
      expect(calls).to eq(%i[changed changed])
    end

    it 'runs again for a job that came after it took the last one' do
      runs = 0
      gate = Queue.new
      waiting = Queue.new
      thread = keeper.start('c_again') do
        runs += 1
        keeper.next_job('c_again')
        if runs == 1
          waiting << :yes
          gate.pop
        end
      end
      expect(keeper.start('c_again') { raise 'not run' }).to be_nil
      waiting.pop
      keeper.enqueue(job('c_again'))
      gate << :go
      thread.join
      expect(runs).to eq(2)
    end

    it 'holds a bounded number of jobs per chat' do
      (described_class::JOBS_PER_CHAT + 5).times { keeper.enqueue(job('c_many')) }
      expect(described_class::JOBS['c_many'].size).to eq(described_class::JOBS_PER_CHAT)
    end
  end

  describe 'the page' do
    it 'shows what a model wrote as text: no markup, link, image or emphasis' do
      text = '<script>x</script> [a](javascript:1) ![i](x.png) **b** _c_ `d`'
      shown = Monadic::TurnState::Notes.inline(text)
      expect(shown).not_to match(/(?<!\\)[<>\[\]*_`!]/)
      expect(shown.delete('\\')).to eq(text)
    end
  end
end
