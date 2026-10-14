# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require_relative '../../../apps/knowledge_base/knowledge_base_tools'

# The Knowledge Base app's tools must use the Library's scope model
# (scope_app = an app class name or "Global"). These examples call the
# tools with a stubbed store and Manager, so they need no Qdrant.
RSpec.describe KnowledgeBaseTools do
  let(:host) { Class.new { include KnowledgeBaseTools }.new }
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:manager) { Monadic::Library::Manager }

  before do
    allow(host).to receive(:with_kb_store).and_yield(store)
    stub_const('APPS', { 'ChatOpenAI' => double, 'JupyterNotebookGrok' => double })
  end

  describe '#update_conversation_scope' do
    it 'sets an entry to Global' do
      expect(manager).to receive(:update_scope_app)
        .with(store: store, conversation_id: 'c1', scope_app: 'Global').and_return(true)
      expect(host.update_conversation_scope(conversation_id: 'c1', scope: 'global'))
        .to eq('✓ c1 now belongs to Global.')
    end

    it 'accepts the label shown in the UI and stores the app class name' do
      expect(manager).to receive(:update_scope_app)
        .with(store: store, conversation_id: 'c1', scope_app: 'JupyterNotebookGrok').and_return(true)
      expect(host.update_conversation_scope(conversation_id: 'c1', scope: 'Jupyter Notebook (Grok)'))
        .to eq('✓ c1 now belongs to Jupyter Notebook (Grok).')
    end

    it 'accepts the app class name' do
      expect(manager).to receive(:update_scope_app)
        .with(store: store, conversation_id: 'c1', scope_app: 'ChatOpenAI').and_return(true)
      host.update_conversation_scope(conversation_id: 'c1', scope: 'ChatOpenAI')
    end

    it 'refuses an app that is not registered and changes nothing' do
      expect(manager).not_to receive(:update_scope_app)
      expect(host.update_conversation_scope(conversation_id: 'c1', scope: 'Chat (Nowhere)'))
        .to start_with("❌ No app named 'Chat (Nowhere)'")
    end
  end

  describe '#library_stats' do
    it 'reports the total and one line per scope, Global first' do
      allow(manager).to receive(:library_stats).with(store: store).and_return(
        conversations_total: 5,
        conversations_by_scope: { 'ChatOpenAI' => 3, 'Global' => 2 }
      )
      expect(host.library_stats).to eq(
        "Knowledge Base contents: 5 entries\n- Global: 2\n- Chat (OpenAI): 3"
      )
    end
  end

  describe '#import_conversation_from_text' do
    let(:result) { { conversation_id: 'c9', importer: 'Plain', counts: { turns: 2, summary: 1 } } }

    it 'imports as Global by default' do
      expect(manager).to receive(:import_from_text)
        .with(store: store, input: 'A: hi', options: {}, scope_app: 'Global').and_return(result)
      expect(host.import_conversation_from_text(input: 'A: hi')).to include('(scope: Global)')
    end

    it 'imports into the app the user names' do
      expect(manager).to receive(:import_from_text)
        .with(store: store, input: 'A: hi', options: { title: 'T' }, scope_app: 'ChatOpenAI').and_return(result)
      expect(host.import_conversation_from_text(input: 'A: hi', title: 'T', scope: 'Chat (OpenAI)'))
        .to include('(scope: Chat (OpenAI))')
    end
  end

  describe 'listing and details' do
    it 'shows the scope of each entry' do
      allow(manager).to receive(:list_conversations).and_return(
        [{ conversation_id: 'c1', title: 'T', scope_app: 'ChatOpenAI', turns_count: 1 }]
      )
      expect(host.list_conversations).to include('scope=Chat (OpenAI)')
    end

    it 'shows the scope in the details' do
      allow(manager).to receive(:get_conversation_details).and_return(
        { conversation_id: 'c1', title: 'T', scope_app: 'Global' }
      )
      expect(host.get_conversation_details(conversation_id: 'c1')).to include('scope: Global')
    end
  end
end
