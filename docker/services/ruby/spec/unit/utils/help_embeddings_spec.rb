# frozen_string_literal: true

require 'spec_helper'
require 'monadic/utils/help_embeddings'
require_relative '../../../apps/monadic_help/monadic_help_tools'

# Behavioural tests against a fully fake VectorStore + Embeddings client. The
# point is to lock in the public API contract that monadic_help_tools.rb (and
# the MCP adapter) rely on, not to test Qdrant itself.
RSpec.describe HelpEmbeddings do
  let(:store) { instance_double(Monadic::VectorStore::Base) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }
  let(:db) { described_class.new(vector_store: store, embeddings: embeddings) }

  before do
    allow(embeddings).to receive(:embed_query).and_return([0.1, 0.2, 0.3])
  end

  def hit(id:, score:, payload:)
    { 'id' => id, 'score' => score, 'payload' => { 'is_internal' => false }.merge(payload) }
  end

  describe '#find_closest_text' do
    it 'searches help_items with a query embedding and joins doc-level title' do
      expect(store).to receive(:search).with(
        hash_including(
          collection: 'help_items',
          vector: [0.1, 0.2, 0.3],
          vector_name: 'content',
          limit: 5
        )
      ).and_return([
        hit(id: 11, score: 0.91,
            payload: { 'doc_id' => 1, 'text' => 'snippet', 'position' => 0,
                       'heading' => 'h', 'language' => 'en' })
      ])
      expect(store).to receive(:retrieve_points).with(
        collection: 'help_docs', ids: [1]
      ).and_return([{ 'id' => 1, 'payload' => { 'is_internal' => false, 'title' => 'T', 'file_path' => 'a.md', 'section' => 's' } }])

      results = db.find_closest_text('what is monad?', top_n: 5)
      expect(results.size).to eq(1)
      expect(results.first).to include(
        text: 'snippet', doc_id: 1, title: 'T', file_path: 'a.md', similarity: 0.91
      )
    end

    it 'filters out internal docs by default and includes them when asked' do
      expect(store).to receive(:search).with(
        hash_including(filter: { must: [{ key: 'is_internal', match: { value: false } }] })
      ).and_return([])

      db.find_closest_text('q')

      expect(store).to receive(:search).with(hash_including(filter: nil)).and_return([])

      db.find_closest_text('q', include_internal: true)
    end
  end

  describe '#find_closest_text_multi' do
    it 'caps chunks per doc and limits to top_n unique docs' do
      raw_hits = (1..6).map do |i|
        hit(id: i, score: 0.9 - (i * 0.05),
            payload: { 'doc_id' => (i <= 3 ? 1 : 2), 'text' => "t#{i}", 'position' => i })
      end
      allow(store).to receive(:search).and_return(raw_hits)
      allow(store).to receive(:retrieve_points).and_return([{ 'id' => 1, 'payload' => { 'is_internal' => false } }])

      results = db.find_closest_text_multi('q', chunks_per_result: 2, top_n: 2)
      doc_ids = results.map { |r| r[:doc_id] }
      expect(doc_ids.tally).to eq(1 => 2, 2 => 2)
    end
  end

  describe '#find_closest_doc' do
    it 'searches help_docs and forwards a language filter when given' do
      expect(store).to receive(:search).with(
        hash_including(
          collection: 'help_docs',
          filter: { must: [{ key: 'language', match: { value: 'ja' } },
                           { key: 'is_internal', match: { value: false } }] }
        )
      ).and_return([
        hit(id: 7, score: 0.8,
            payload: { 'title' => 'T', 'file_path' => 'a.md', 'language' => 'ja',
                       'items' => 3, 'metadata' => { 'category' => 'guide' } })
      ])

      results = db.find_closest_doc('q', top_n: 1, language: 'ja')
      expect(results.first).to include(doc_id: 7, language: 'ja', items: 3)
    end
  end

  describe '#list_titles' do
    it 'paginates via scroll until next is nil' do
      expect(store).to receive(:scroll).and_return(
        { points: [{ 'id' => 1, 'payload' => { 'title' => 'A' } }], next: 'cursor1' },
        { points: [{ 'id' => 2, 'payload' => { 'title' => 'B' } }], next: nil }
      )
      titles = db.list_titles
      expect(titles.map { |t| t[:title] }).to eq(%w[A B])
    end
  end

  describe '#get_text_snippets' do
    it 'returns items sorted by position' do
      allow(store).to receive(:retrieve_points).with(collection: 'help_docs', ids: [99])
        .and_return([{ 'id' => 99, 'payload' => { 'is_internal' => false } }])
      allow(store).to receive(:scroll).and_return(
        { points: [
          { 'id' => 1, 'payload' => { 'text' => 'b', 'position' => 1 } },
          { 'id' => 2, 'payload' => { 'text' => 'a', 'position' => 0 } }
        ], next: nil }
      )
      snippets = db.get_text_snippets(99)
      expect(snippets.map { |s| s[:text] }).to eq(%w[a b])
    end
  end

  describe '#search (MCP alias)' do
    it 'returns title/content/distance shape' do
      allow(store).to receive(:search).and_return([
        hit(id: 1, score: 0.85, payload: { 'doc_id' => 1, 'text' => 'snippet' })
      ])
      allow(store).to receive(:retrieve_points).and_return([{ 'id' => 1, 'payload' => { 'is_internal' => false, 'title' => 'T' } }])

      results = db.search(query: 'q', num_results: 1)
      expect(results.first).to include(title: 'T', content: 'snippet')
      expect(results.first[:distance]).to be_within(0.001).of(0.15)
    end
  end

  describe '#get_stats' do
    it 'counts documents by language and reports averages' do
      allow(store).to receive(:scroll).with(hash_including(collection: 'help_docs')).and_return(
        { points: [
          { 'id' => 1, 'payload' => { 'language' => 'en', 'items' => 4 } },
          { 'id' => 2, 'payload' => { 'language' => 'en', 'items' => 8 } },
          { 'id' => 3, 'payload' => { 'language' => 'ja', 'items' => 6 } }
        ], next: nil }
      )
      items = [1] * 4 + [2] * 8 + [3] * 6
      allow(store).to receive(:scroll).with(hash_including(collection: 'help_items')).and_return(
        { points: items.map { |id| { 'payload' => { 'doc_id' => id } } }, next: nil }
      )

      stats = db.get_stats
      expect(stats[:documents_by_language]).to eq('en' => 2, 'ja' => 1)
      expect(stats[:total_items]).to eq(18)
      expect(stats[:avg_items_per_doc]).to eq(6.0)
    end
  end

  context 'with mixed public, internal, and unclassified points' do
    # Exercise the facade against a store double that applies the requested
    # payload filters. Parent visibility must still be enforced by the facade.
    let(:docs) do
      [
        [1, false, 'Public', 'guide', 'en'],
        [2, true, 'Internal', 'private', 'en'],
        [3, nil, 'Unclassified', 'unknown', 'ja'],
        [4, false, 'Public JA', 'guide', 'ja']
      ].map do |id, internal, title, category, language|
        payload = { 'title' => title, 'section' => 'guide', 'language' => language,
                    'file_path' => "doc#{id}.md", 'items' => 99,
                    'metadata' => { 'category' => category } }
        payload['is_internal'] = internal unless internal.nil?
        { 'id' => id, 'score' => 0.9, 'payload' => payload }
      end
    end

    let(:items) do
      [
        [11, 1, false, 'public text'],
        [12, 1, true, 'internal child'],
        [13, 1, nil, 'unclassified child'],
        [21, 2, false, 'public child of internal parent'],
        [22, 2, true, 'internal text'],
        [31, 3, false, 'public child of unclassified parent'],
        [41, 4, false, 'public ja text'],
        [51, 999, false, 'orphan text']
      ].map do |id, doc_id, internal, text|
        payload = { 'doc_id' => doc_id, 'text' => text, 'position' => id,
                    'language' => 'en', 'metadata' => {} }
        payload['is_internal'] = internal unless internal.nil?
        { 'id' => id, 'score' => 0.9, 'payload' => payload }
      end
    end

    def filtered_points(points, filter)
      points.select do |point|
        Array(filter && filter[:must]).all? do |condition|
          value = condition[:key].split('.').reduce(point['payload']) { |obj, key| obj&.[](key) }
          value == condition.fetch(:match).fetch(:value)
        end
      end
    end

    before do
      collections = { 'help_docs' => docs, 'help_items' => items }
      allow(store).to receive(:search) do |collection:, filter:, limit:, **|
        filtered_points(collections.fetch(collection), filter).take(limit)
      end
      allow(store).to receive(:scroll) do |collection:, filter:, offset:, **|
        points = filtered_points(collections.fetch(collection), filter)
        # Force multiple pages, including pages containing only hidden data
        # when the caller opts into internal points.
        start = offset || 0
        page = points.slice(start, 2) || []
        { points: page, next: start + page.size < points.size ? start + page.size : nil }
      end
      allow(store).to receive(:retrieve_points) do |collection:, ids:|
        collections.fetch(collection).select { |point| ids.include?(point['id']) }
      end
    end

    it 'filters child and parent visibility across all text search APIs' do
      expect(db.find_closest_text('q').map { |r| r[:text] }).to eq(['public text', 'public ja text'])
      expect(db.find_closest_text_multi('q').map { |r| r[:text] }).to eq(['public text', 'public ja text'])
      expect(db.search(query: 'q', num_results: 10).map { |r| r[:content] })
        .to eq(['public text', 'public ja text'])

      expected = items.reject { |point| point.dig('payload', 'doc_id') == 999 }
                      .map { |point| point.dig('payload', 'text') }
      expect(db.find_closest_text('q', include_internal: true).map { |r| r[:text] }).to eq(expected)
      expect(db.find_closest_text_multi('q', include_internal: true).map { |r| r[:text] }).to eq(expected)
      # search caps at one chunk per document.
      expect(db.search(query: 'q', num_results: 10, include_internal: true).map { |r| r[:title] })
        .to eq(['Public', 'Internal', 'Unclassified', 'Public JA'])
    end

    it 'filters document search and title listing without losing language constraints' do
      expect(db.find_closest_doc('q').map { |r| r[:doc_id] }).to eq([1, 4])
      expect(db.list_titles.map { |r| r[:doc_id] }).to eq([1, 4])
      expect(db.find_closest_doc('q', include_internal: true).map { |r| r[:doc_id] }).to eq([1, 2, 3, 4])
      expect(db.list_titles(include_internal: true).map { |r| r[:doc_id] }).to eq([1, 2, 3, 4])
      expect(db.find_closest_doc('q', language: 'ja').map { |r| r[:doc_id] }).to eq([4])
      expect(db.list_titles(language: 'ja').map { |r| r[:doc_id] }).to eq([4])
      expect(db.find_closest_doc('q', language: 'ja', include_internal: true).map { |r| r[:doc_id] })
        .to eq([3, 4])
      expect(db.list_titles(language: 'ja', include_internal: true).map { |r| r[:doc_id] }).to eq([3, 4])
    end

    it 'checks the parent before returning snippets by ID and hides nonpublic children' do
      expect(db.get_text_snippets(1).map { |r| r[:text] }).to eq(['public text'])
      [2, 3, 999, nil].each { |id| expect(db.get_text_snippets(id)).to eq([]) }
      expect(db.get_text_snippets(1, include_internal: true).map { |r| r[:text] })
        .to eq(['public text', 'internal child', 'unclassified child'])
      expect(db.get_text_snippets(2, include_internal: true).size).to eq(2)
      expect(db.get_text_snippets(3, include_internal: true).size).to eq(1)
      expect(db.get_text_snippets(999, include_internal: true)).to eq([])
    end

    it 'filters category names, documents and their contents' do
      expect(db.get_unique_categories).to eq(['guide'])
      expect(db.get_unique_categories(include_internal: true)).to eq(%w[guide private unknown])
      expect(db.get_by_category('guide').map { |r| r[:content] }).to eq(['public text', 'public ja text'])
      expect(db.get_by_category('private')).to eq([])
      expect(db.get_by_category('unknown')).to eq([])
      expect(db.get_by_category('private', include_internal: true).first[:content])
        .to eq("public child of internal parent\n\ninternal text")
      expect(db.get_by_category('guide', include_internal: true).first[:content])
        .to include('internal child', 'unclassified child')
      expect(db.get_by_category('unknown', include_internal: true).first[:title]).to eq('Unclassified')
    end

    it 'counts only visible children of visible parents, ignoring cached document counts' do
      expect(db.get_stats).to eq(documents_by_language: { 'en' => 1, 'ja' => 1 },
                                 total_items: 2, avg_items_per_doc: 1.0)
      expect(db.get_stats(include_internal: true))
        .to eq(documents_by_language: { 'en' => 2, 'ja' => 2 }, total_items: 7, avg_items_per_doc: 1.75)
    end

    context 'through Help tools' do
      let(:host) { Object.new.extend(MonadicHelpTools) }

      around do |example|
        previous = ENV.delete('DEBUG_MODE')
        example.run
      ensure
        previous.nil? ? ENV.delete('DEBUG_MODE') : ENV['DEBUG_MODE'] = previous
      end

      before { allow(host).to receive(:help_embeddings_db).and_return(db) }

      it 'excludes internal data through all four tools with DEBUG_MODE unset' do
        expect(host.find_help_topics(text: 'q')[:results].map { |r| r[:doc_id] }).to eq([1, 4])
        expect(host.search_help_by_section(text: 'q', section: 'guide')[:results].map { |r| r[:doc_id] })
          .to eq([1, 4])
        sections = host.list_help_sections[:sections]
        expect(sections.flat_map { |section| section[:documents].map { |doc| doc[:doc_id] } }).to eq([1, 4])
        expect(host.get_help_document(doc_id: 1)[:content]).to eq('public text')
        [2, 3].each do |id|
          expect(host.get_help_document(doc_id: id)).to include(content: '', snippets_count: 0)
        end
      end

      it 'passes DEBUG_MODE through all tools and honors explicit exclusion' do
        ENV['DEBUG_MODE'] = 'true'
        expect(db.list_titles.map { |r| r[:doc_id] }).to eq([1, 4])
        expect(db.find_closest_text('q').map { |r| r[:doc_id] }).to eq([1, 4])
        expect(host.find_help_topics(text: 'q')[:results].map { |r| r[:doc_id] }).to eq([1, 2, 3, 4])
        expect(host.search_help_by_section(text: 'q', section: 'guide', top_n: 10)[:results]
                   .map { |r| r[:doc_id] }).to eq([1, 2, 3, 4])
        expect(host.list_help_sections[:sections].first[:documents].size).to eq(4)
        expect(host.get_help_document(doc_id: 2)[:snippets_count]).to eq(2)
        expect(host.find_help_topics(text: 'q', include_internal: false)[:results].map { |r| r[:doc_id] })
          .to eq([1, 4])
        expect(host.search_help_by_section(text: 'q', section: 'guide', include_internal: false)[:results]
                   .map { |r| r[:doc_id] }).to eq([1, 4])
        expect(host.list_help_sections(include_internal: false)[:sections].first[:documents].size).to eq(2)
        expect(host.get_help_document(doc_id: 2, include_internal: false)[:content]).to eq('')
      end

      it 'accepts explicit inclusion without DEBUG_MODE' do
        expect(host.find_help_topics(text: 'q', include_internal: true)[:results].size).to eq(4)
        expect(host.search_help_by_section(text: 'q', section: 'guide', top_n: 10,
                                          include_internal: true)[:results].size).to eq(4)
        expect(host.list_help_sections(include_internal: true)[:sections].first[:documents].size).to eq(4)
        expect(host.get_help_document(doc_id: 2, include_internal: true)[:snippets_count]).to eq(2)
      end
    end
  end

  describe '#upsert_doc and #upsert_item' do
    it 'wraps the embedding under the named "content" vector' do
      expect(store).to receive(:upsert_points).with(
        hash_including(
          collection: 'help_docs',
          points: [{
            id: 5,
            vector: { 'content' => [0.1, 0.2] },
            payload: hash_including('title' => 'T', 'language' => 'en')
          }]
        )
      )
      db.upsert_doc(id: 5, embedding: [0.1, 0.2], title: 'T', language: 'en')
    end

    it 'stores doc_id on items so they can be filtered later' do
      expect(store).to receive(:upsert_points).with(
        hash_including(
          collection: 'help_items',
          points: [{
            id: 11,
            vector: { 'content' => [0.5] },
            payload: hash_including('doc_id' => 5, 'text' => 'hello', 'position' => 0)
          }]
        )
      )
      db.upsert_item(id: 11, embedding: [0.5], doc_id: 5, text: 'hello', position: 0)
    end
  end

  describe '#bootstrap_collections!' do
    it 'creates only the missing collections' do
      allow(store).to receive(:collection_exists?).with(name: 'help_docs').and_return(true)
      allow(store).to receive(:collection_exists?).with(name: 'help_items').and_return(false)

      expect(store).to receive(:create_collection).with(hash_including(name: 'help_items'))
      expect(store).not_to receive(:create_collection).with(hash_including(name: 'help_docs'))

      db.bootstrap_collections!
    end
  end

  describe '#data_loaded?' do
    it 'returns true when help_docs has at least one point' do
      allow(store).to receive(:collection_exists?).and_return(true)
      allow(store).to receive(:count).with(collection: 'help_docs').and_return(42)
      expect(db.data_loaded?).to be true
    end

    it 'returns false on an empty database' do
      allow(store).to receive(:collection_exists?).and_return(true)
      allow(store).to receive(:count).with(collection: 'help_docs').and_return(0)
      expect(db.data_loaded?).to be false
    end
  end

  describe 'visibility filter' do
    # The public-only condition is added to the caller's filter. Every other
    # clause must survive, or a filter with should / must_not would silently
    # lose its conditions once it is made public-only.
    let(:filter) do
      { must: [{ key: 'language', match: { value: 'en' } }],
        must_not: [{ key: 'metadata.category', match: { value: 'x' } }] }
    end

    it 'keeps the clauses it was given and adds the public-only condition' do
      result = db.send(:visibility_filter, filter)
      expect(result[:must_not]).to eq(filter[:must_not])
      expect(result[:must]).to include({ key: 'language', match: { value: 'en' } },
                                       { key: 'is_internal', match: { value: false } })
      expect(filter[:must].size).to eq(1)
    end

    it 'returns the filter unchanged when internal points are requested' do
      expect(db.send(:visibility_filter, filter, include_internal: true)).to equal(filter)
    end
  end
end
