# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'monadic/library'
require_relative '../../support/vector_service_helper'

# End-to-end smoke test for the Library subsystem against real Qdrant +
# embeddings containers: entries written by import_conversation are found
# by a real cascade_search round-trip. Skips automatically when the dev
# overlay can't bring the services up on localhost.
RSpec.describe 'Library subsystem integration smoke', :integration do
  before(:all) do
    VectorServiceHelper.ensure_dev_overlay!

    @store = Monadic::Library::Store.new
    @suffix = "smoke_#{Process.pid}_#{Time.now.to_i}"
    @cleanup_ids = []
  end

  after(:all) do
    @cleanup_ids.each do |id|
      @store.delete_conversation(id)
    rescue StandardError
      # best effort — collection may already be in a torn-down state.
    end
  end

  # Build a minimal-but-valid `monadic-conversation` v1 hash. Each
  # ingestion gets its own UUID so the after(:all) cleanup can target
  # exactly the points this spec wrote (no risk of touching the
  # production library_summaries / library_turns rows from interactive
  # use of the same database).
  def ingest(label:, body:)
    conv_id = SecureRandom.uuid
    @cleanup_ids << conv_id
    conversation = {
      'format_version' => '1.0',
      'conversation_id' => conv_id,
      'conversation_metadata' => {
        'source' => "lib-smoke-#{@suffix}",
        'title' => "smoke: #{label}",
        'language' => 'en',
        'license' => 'private'
      },
      'participants' => [
        { 'id' => 'human', 'role' => 'human' },
        { 'id' => 'assistant', 'role' => 'assistant' }
      ],
      'messages' => [
        { 'id' => 'm1', 'speaker' => { 'id' => 'human' }, 'text' => body },
        { 'id' => 'm2', 'speaker' => { 'id' => 'assistant' }, 'text' => "Echo: #{body}" }
      ]
    }
    Monadic::Library::Manager.import_conversation(store: @store, conversation: conversation)
    conv_id
  end

  it 'cascade_search finds every entry (the Knowledge Base is one shelf)' do
    body = "Discussion of the cosmic microwave background and CMB anisotropy spectrum #{@suffix}"
    first_id  = ingest(label: 'first', body: body)
    second_id = ingest(label: 'second', body: body)

    hits = Monadic::Library::Retriever.cascade_search(body, store: @store, top_n: 10)
    visible = hits.map { |h| h[:conversation_id] }.uniq

    expect(visible).to include(first_id, second_id)
  end
end
