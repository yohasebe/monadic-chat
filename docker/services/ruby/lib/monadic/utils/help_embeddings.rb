# frozen_string_literal: true

require 'json'

require_relative '../vector_store'
require_relative '../embeddings'

# HelpEmbeddings provides retrieval over the Monadic Chat documentation corpus.
# Storage is delegated to Qdrant via Monadic::VectorStore; embedding inference
# is delegated to the embeddings_service via Monadic::Embeddings::Client.
#
# This class intentionally does not subclass anything: PDF retrieval uses a
# different concrete class (Monadic::PdfStore) so we can keep schemas, payload
# shapes, and tuning knobs decoupled.
class HelpEmbeddings
  Schema = Monadic::VectorStore::Schema

  COLLECTIONS = [Schema::HELP_DOCS, Schema::HELP_ITEMS].freeze

  def initialize(vector_store: Monadic::VectorStore.default_backend,
                 embeddings: Monadic::Embeddings.default_client)
    @store = vector_store
    @embeddings = embeddings
  end

  # Expose for the loader and for tests; callers should generally not poke
  # the underlying store directly.
  attr_reader :store, :embeddings

  # ─── Read API (used by monadic_help_tools.rb) ──────────────────────

  def find_closest_text(text, top_n: 10, include_internal: false)
    vec = embed_query(text)
    filter = include_internal ? nil : without_internal_filter
    hits = @store.search(
      collection: Schema::HELP_ITEMS,
      vector: vec, vector_name: 'content',
      filter: filter, limit: top_n
    )
    hits.map { |hit| item_hit_to_row(hit) }
  end

  # Group nearest items by document so a single document does not flood
  # the result list. Returns at most chunks_per_result chunks per doc.
  def find_closest_text_multi(text, chunks_per_result: 3, top_n: 5, include_internal: false)
    initial = find_closest_text(text,
                                top_n: top_n * chunks_per_result,
                                include_internal: include_internal)
    grouped = {}
    initial.each do |row|
      doc_id = row[:doc_id]
      grouped[doc_id] ||= []
      grouped[doc_id] << row if grouped[doc_id].length < chunks_per_result
    end
    grouped.values.take(top_n).flatten
  end

  def find_closest_doc(text, top_n: 5, language: nil)
    vec = embed_query(text)
    filter = language ? language_filter(language) : nil
    hits = @store.search(
      collection: Schema::HELP_DOCS,
      vector: vec, vector_name: 'content',
      filter: filter, limit: top_n
    )
    hits.map { |hit| doc_hit_to_row(hit) }
  end

  def list_titles(language: nil)
    filter = language ? language_filter(language) : nil
    scroll_all(Schema::HELP_DOCS, filter: filter).map do |point|
      payload = point['payload'] || {}
      {
        doc_id: point['id'],
        title: payload['title'],
        file_path: payload['file_path'],
        section: payload['section'],
        language: payload['language']
      }
    end
  end

  def get_text_snippets(doc_id)
    items = scroll_all(Schema::HELP_ITEMS, filter: doc_id_filter(doc_id))
    items
      .map { |p| p['payload'] || {} }
      .sort_by { |p| (p['position'] || 0).to_i }
      .map do |p|
        {
          text: p['text'],
          position: p['position'],
          heading: p['heading'],
          metadata: p['metadata'] || {}
        }
      end
  end

  # MCP adapter compatibility: tightened formatting around find_closest_text_multi.
  def search(query:, num_results: 3)
    rows = find_closest_text_multi(query, chunks_per_result: 1, top_n: num_results)
    rows.map do |r|
      {
        title: r[:title],
        content: r[:text],
        metadata: r[:metadata],
        distance: 1.0 - r[:similarity].to_f
      }
    end
  end

  def get_stats
    docs = scroll_all(Schema::HELP_DOCS)
    by_lang = Hash.new(0)
    docs.each do |p|
      by_lang[p.dig('payload', 'language') || 'unknown'] += 1
    end
    total_items = @store.count(collection: Schema::HELP_ITEMS)
    avg = if docs.empty?
            0.0
          else
            (docs.sum { |p| (p.dig('payload', 'items') || 0).to_i }.to_f / docs.size).round(2)
          end
    {
      documents_by_language: by_lang,
      total_items: total_items,
      avg_items_per_doc: avg
    }
  end

  def get_unique_categories
    scroll_all(Schema::HELP_DOCS)
      .map { |p| p.dig('payload', 'metadata', 'category') }
      .compact
      .uniq
      .sort
  end

  def get_by_category(category)
    scroll_all(Schema::HELP_DOCS, filter: category_filter(category)).map do |doc|
      payload = doc['payload'] || {}
      doc_id = doc['id']
      items = scroll_all(Schema::HELP_ITEMS, filter: doc_id_filter(doc_id))
              .sort_by { |i| (i.dig('payload', 'position') || 0).to_i }
      content = items.map { |i| i.dig('payload', 'text') }.compact.join("\n\n")
      {
        doc_id: doc_id,
        title: payload['title'],
        file_path: payload['file_path'],
        section: payload['section'],
        language: payload['language'],
        metadata: payload['metadata'] || {},
        content: content
      }
    end
  end

  # ─── Build / bootstrap API ─────────────────────────────────────────

  # Insert or update a single document. Caller supplies a pre-computed
  # embedding (build pipelines compute them in batches before calling).
  def upsert_doc(doc)
    @store.upsert_points(
      collection: Schema::HELP_DOCS,
      points: [{
        id: doc.fetch(:id),
        vector: { 'content' => doc.fetch(:embedding) },
        payload: doc_payload(doc)
      }]
    )
  end

  def upsert_item(item)
    @store.upsert_points(
      collection: Schema::HELP_ITEMS,
      points: [{
        id: item.fetch(:id),
        vector: { 'content' => item.fetch(:embedding) },
        payload: item_payload(item)
      }]
    )
  end

  # Drop both collections and recreate them empty.
  def clear_all_help_data
    COLLECTIONS.each { |name| @store.delete_collection(name: name) }
    bootstrap_collections!
  end

  # Create collections if they do not yet exist. Idempotent.
  def bootstrap_collections!
    COLLECTIONS.each do |name|
      next if @store.collection_exists?(name: name)
      defn = Schema::DEFINITIONS[name]
      @store.create_collection(
        name: name,
        vectors: defn[:vectors],
        payload_indexes: defn[:payload_indexes]
      )
    end
  end

  def data_loaded?
    bootstrap_collections!
    @store.count(collection: Schema::HELP_DOCS) > 0
  end

  private

  def embed_query(text)
    @embeddings.embed_query(text)
  end

  def doc_payload(doc)
    {
      'title' => doc[:title],
      'file_path' => doc[:file_path],
      'section' => doc[:section],
      'language' => doc[:language] || 'en',
      'items' => doc[:items] || 0,
      'is_internal' => doc[:is_internal] || false,
      'metadata' => doc[:metadata] || {}
    }
  end

  def item_payload(item)
    {
      'doc_id' => item[:doc_id],
      'text' => item[:text],
      'position' => item[:position],
      'heading' => item[:heading],
      'language' => item[:language] || 'en',
      'is_internal' => item[:is_internal] || false,
      'metadata' => item[:metadata] || {}
    }
  end

  def item_hit_to_row(hit)
    payload = hit['payload'] || {}
    doc_payload = fetch_doc_payload(payload['doc_id'])
    {
      text: payload['text'],
      doc_id: payload['doc_id'],
      position: payload['position'],
      heading: payload['heading'],
      metadata: payload['metadata'] || {},
      title: doc_payload['title'],
      file_path: doc_payload['file_path'],
      section: doc_payload['section'],
      language: payload['language'],
      similarity: hit['score'].to_f
    }
  end

  def doc_hit_to_row(hit)
    payload = hit['payload'] || {}
    {
      doc_id: hit['id'],
      title: payload['title'],
      file_path: payload['file_path'],
      section: payload['section'],
      language: payload['language'],
      items: payload['items'].to_i,
      metadata: payload['metadata'] || {},
      similarity: hit['score'].to_f
    }
  end

  def fetch_doc_payload(doc_id)
    return {} if doc_id.nil?
    points = @store.retrieve_points(collection: Schema::HELP_DOCS, ids: [doc_id])
    points.first&.dig('payload') || {}
  end

  def without_internal_filter
    { must: [{ key: 'is_internal', match: { value: false } }] }
  end

  def language_filter(lang)
    { must: [{ key: 'language', match: { value: lang } }] }
  end

  def doc_id_filter(doc_id)
    { must: [{ key: 'doc_id', match: { value: doc_id.to_i } }] }
  end

  def category_filter(category)
    { must: [{ key: 'metadata.category', match: { value: category } }] }
  end

  def scroll_all(collection, filter: nil, batch_size: 256)
    results = []
    offset = nil
    loop do
      page = @store.scroll(
        collection: collection,
        filter: filter,
        limit: batch_size,
        offset: offset
      )
      results.concat(page[:points])
      break if page[:next].nil?
      offset = page[:next]
    end
    results
  end
end
