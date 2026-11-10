# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/monadic/utils/websocket'
require_relative '../../../../lib/monadic/utils/privacy/words'

# Speech of a chat that hides its words with a word table: what a speech
# service is given to read.
RSpec.describe 'Speech in a chat with a word table' do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) { { parameters: {}, messages: [] }.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:errors) { [] }

  before do
    table.confirm!('Ada Lovelace', 'PERSON')
    allow(host).to receive(:send_error) { |message, *| errors << message }
  end

  after { words::LOCK.synchronize { words::TABLES.clear } }

  def spoken(text, provider = nil)
    host.send(:privacy_sanitize_tts_text, text, session, provider)
  end

  it 'reads each word as its type and number, written out or as its placeholder' do
    expect(spoken('Ada Lovelace wrote <<PERSON_1>>.')).to eq('PERSON 1 wrote PERSON 1.')
    expect(errors).to be_empty
  end

  it 'reads nothing when what the speech service is given holds a word' do
    allow(host).to receive(:tts_text_as_sent).and_return('Ada Lovelace')
    expect(spoken('a reply', 'elevenlabs-v3')).to be_nil
    expect(errors.size).to eq(1)
  end

  it "reads nothing when the chat's table is not there" do
    words::LOCK.synchronize { words::TABLES.clear }
    expect(spoken('Ada Lovelace')).to be_nil
    expect(errors.size).to eq(1)
  end
end
