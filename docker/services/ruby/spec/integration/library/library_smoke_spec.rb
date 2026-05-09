# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'monadic/library'
require_relative '../../support/vector_service_helper'

# End-to-end smoke test for the Library subsystem against real Qdrant +
# embeddings containers. Verifies the scope_app filter contract that
# `library_search` relies on for per-app scoping. Skips automatically
# when the dev overlay can't bring the services up on localhost.
#
# Why this test exists:
#   The unit specs already cover the *shape* of the Qdrant filter
#   produced for `scope_app IN [current_app, "Global"]`. This test goes
#   one layer deeper and checks that a real Qdrant instance honours
#   that filter shape during a real cascade_search round-trip.
#   Without this gate, a future Qdrant API change (or a typo in the
#   filter key) could let "scope_app: ChatClaude" entries leak into a
#   ChatOpenAI session despite the unit tests passing.
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
  def ingest(scope_app:, body:)
    conv_id = SecureRandom.uuid
    @cleanup_ids << conv_id
    conversation = {
      'format_version' => '1.0',
      'conversation_id' => conv_id,
      'conversation_metadata' => {
        'source' => "lib-smoke-#{@suffix}",
        'title' => "smoke: #{scope_app}",
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
    Monadic::Library::Manager.import_conversation(
      store: @store, conversation: conversation, scope_app: scope_app
    )
    conv_id
  end

  it 'cascade_search returns only entries whose scope_app matches current_app or Global' do
    # Three entries with deliberately near-identical text so retrieval
    # ranking does not accidentally hide one of them. The body is
    # specific enough to be the obvious top hit for any sane embedding.
    body = "Discussion of the cosmic microwave background and CMB anisotropy spectrum #{@suffix}"
    open_id   = ingest(scope_app: 'ChatOpenAI', body: body)
    claude_id = ingest(scope_app: 'ChatClaude', body: body)
    global_id = ingest(scope_app: 'Global',     body: body)

    # Search as ChatOpenAI: must see OpenAI + Global, NOT Claude.
    hits = Monadic::Library::Retriever.cascade_search(
      body, store: @store, app_name: 'ChatOpenAI', top_n: 10
    )
    visible = hits.map { |h| h[:conversation_id] }.uniq

    expect(visible).to include(open_id),   "expected OpenAI-scoped entry to be visible to ChatOpenAI"
    expect(visible).to include(global_id), "expected Global entry to be visible to every app"
    expect(visible).not_to include(claude_id),
      "ChatClaude-scoped entry must NOT leak into a ChatOpenAI search"
  end

  it 'cascade_search with no app_name (KB UI inventory mode) returns every scope' do
    body = "Renewable energy storage and grid-scale battery economics #{@suffix}"
    open_id   = ingest(scope_app: 'ChatOpenAI', body: body)
    claude_id = ingest(scope_app: 'ChatClaude', body: body)
    global_id = ingest(scope_app: 'Global',     body: body)

    # The Knowledge Base app passes app_name: nil so it can show the
    # full library regardless of scope. We replicate that contract here
    # — without it, the user could not browse entries saved while a
    # different app was active.
    hits = Monadic::Library::Retriever.cascade_search(
      body, store: @store, app_name: nil, top_n: 10
    )
    visible = hits.map { |h| h[:conversation_id] }.uniq

    expect(visible).to include(open_id, claude_id, global_id)
  end
end
