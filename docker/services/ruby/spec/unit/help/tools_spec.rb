# frozen_string_literal: true

require 'spec_helper'
require 'monadic/utils/help_embeddings'
require_relative '../../../apps/monadic_help/monadic_help_tools'

RSpec.describe MonadicHelpTools do
  let(:host) { Object.new.extend(described_class) }
  let(:installation) { instance_double(Monadic::Help::Installation) }
  let(:store) { double('read-only store') }
  let(:embeddings) { double('embeddings', embed_query: [0.1]) }
  let(:db) { HelpEmbeddings.new(vector_store: store, embeddings: embeddings) }
  let(:calls) do
    { find_help_topics: { text: 'query' }, get_help_document: { doc_id: 1 },
      list_help_sections: {}, search_help_by_section: { text: 'query', section: 'guide' } }
  end

  before { allow(Monadic::Help).to receive(:installation).and_return(installation) }

  %w[not_installed legacy installing failed unavailable].each do |state|
    it "returns a structured #{state} guide from every tool without exposing exceptions" do
      allow(installation).to receive(:with_search).and_raise(
        Monadic::Help::Installation::Unavailable.new(state: state, reason: 'private details')
      )
      calls.each do |method, args|
        result = host.public_send(method, **args)
        expect(result).to include(code: 'help_database_unavailable', state: state,
                                  action: { label: 'Help Data', url: '/help/database' })
        expect(result[:error]).to include('Help Data')
        expect(result.to_json).not_to include('private details', 'Unavailable', 'rake')
      end
    end
  end

  it 'holds one lease across item searches and parent document reads for every tool' do
    active = false
    allow(installation).to receive(:with_search) do |&block|
      active = true
      block.call(db)
    ensure
      active = false
    end
    document = { 'id' => 1, 'payload' => { 'title' => 'Guide', 'section' => 'guide', 'is_internal' => false } }
    item = { 'id' => 2, 'score' => 0.9, 'payload' => { 'doc_id' => 1, 'text' => 'Help text', 'is_internal' => false, 'position' => 0 } }
    operations = []
    allow(store).to receive(:search) do |**args|
      expect(active).to be true
      operations << [:search, args[:collection]]
      [item]
    end
    allow(store).to receive(:retrieve_points) do |**args|
      expect(active).to be true
      operations << [:retrieve, args[:collection]]
      [document]
    end
    allow(store).to receive(:scroll) do |**args|
      expect(active).to be true
      operations << [:scroll, args[:collection]]
      { points: args[:collection] == 'help_docs' ? [document] : [item], next: nil }
    end

    calls.each do |method, args|
      result = host.public_send(method, **args)
      expect(result).not_to have_key(:error)
      expect(result.to_json).not_to include('HelpEmbeddings')
      expect(active).to be false
      expect(host.instance_variables).to be_empty
    end
    expect(installation).to have_received(:with_search).exactly(4).times
    expect(operations).to include([:search, 'help_items'], [:retrieve, 'help_docs'],
                                  [:scroll, 'help_docs'], [:scroll, 'help_items'])
  end

  it 'checks availability again on the same tool host after an unavailable call' do
    allow(installation).to receive(:with_search).and_raise(Monadic::Help::Installation::Unavailable.new(state: 'not_installed'))
    expect(host.list_help_sections[:state]).to eq('not_installed')
    allow(installation).to receive(:with_search).and_yield(db)
    allow(store).to receive(:scroll).and_return(points: [], next: nil)
    expect(host.list_help_sections).to eq(sections: [])
    expect(host.instance_variables).to be_empty
  end

  it 'does not leak transport exceptions from a search' do
    allow(installation).to receive(:with_search).and_raise(Monadic::VectorStore::BackendError, 'private details')
    expect(host.list_help_sections).to include(code: 'help_search_failed')
    expect(host.list_help_sections.to_json).not_to include('private details')
  end
end
