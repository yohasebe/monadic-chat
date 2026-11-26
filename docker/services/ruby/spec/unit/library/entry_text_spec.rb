# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'monadic/library/entry_text'

RSpec.describe Monadic::Library::EntryText do
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:record) do
    { conversation_id: 'conv-1', title: 'Tides',
      messages: [{ 'id' => 'm1', 'speaker' => { 'id' => 'u' }, 'text' => 'What are tides?' },
                 { 'id' => 'm2', 'speaker' => { 'id' => 'a' }, 'text' => ' The moon pulls the sea. ' },
                 { 'id' => 'm3', 'speaker' => { 'id' => 'a' }, 'text' => '   ' }],
      participants: [{ 'id' => 'u', 'role' => 'human' }, { 'id' => 'a', 'role' => 'assistant' }] }
  end

  before do
    allow(store).to receive(:original_of).and_return(nil)
  end

  def text_of(rec)
    allow(Monadic::Library::Manager).to receive(:get_conversation_messages).with(store: store, conversation_id: 'conv-1')
                                                                         .and_return(rec)
    described_class.of('conv-1', store: store)
  end

  it "gives a conversation's turns under their speakers, and its version as the SHA-256 of that text" do
    entry = text_of(record)

    expect(entry[:text]).to eq("[User]\nWhat are tides?\n\n[Assistant]\nThe moon pulls the sea.\n")
    expect(entry[:version]).to eq(Digest::SHA256.hexdigest(entry[:text]))
    expect(entry).to include(id: 'conv-1', title: 'Tides', original: nil)
  end

  it "gives a document's sections as they are" do
    doc = record.merge(participants: [{ 'id' => 'u', 'role' => 'narrator' }, { 'id' => 'a', 'role' => 'narrator' }])

    expect(text_of(doc)[:text]).to eq("What are tides?\n\nThe moon pulls the sea.\n")
  end

  it 'gives the same version whatever the entry is called' do
    expect(text_of(record.merge(title: 'Renamed'))[:version]).to eq(text_of(record)[:version])
  end

  it 'says the entry is gone, or was not kept whole' do
    expect { text_of(nil) }.to raise_error(described_class::Missing)
    expect { text_of(record.merge(messages: nil, skipped_reason: 'too_large')) }
      .to raise_error(described_class::Incomplete, 'too_large')
  end

  it 'names the kept original of a document' do
    allow(store).to receive(:original_of).with('conv-1').and_return('sha256' => 'a' * 64)

    expect(text_of(record)[:original]).to eq('sha256' => 'a' * 64)
  end
end
