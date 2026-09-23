# frozen_string_literal: true

require 'spec_helper'
require 'monadic/help'
require 'monadic/help/dump_loader'
require 'monadic/utils/help_embeddings'

RSpec.describe 'Help opt-in initialization' do
  it 'loads the service and former loader without opening clients or importing data' do
    expect(Monadic::VectorStore).not_to receive(:default_backend)
    expect(HelpEmbeddings).not_to receive(:new)
    expect(Monadic::Help::Installation).not_to receive(:new)
    expect(Monadic::Help::DumpLoader).not_to receive(:load)
    load File.expand_path('../../../lib/monadic/help.rb', __dir__)
    load File.expand_path('../../../lib/monadic/utils/help_embeddings_loader.rb', __dir__)
    expect(Object.const_defined?(:HELP_EMBEDDINGS_DB)).to be false
  end

  it 'constructs independent services without touching collections or caching availability' do
    store = double('store with no permitted operations')
    allow(Monadic::VectorStore).to receive(:default_backend).and_return(store)
    first = Monadic::Help.installation
    second = Monadic::Help.installation
    expect(first).to be_a(Monadic::Help::Installation)
    expect(second).not_to equal(first)
  end

  it 'uses the shipped host dump in development and the image dump in containers' do
    previous = ENV.delete('HELP_DATA_DUMP')
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
    host_dump = File.expand_path('../../../help_data/help_db.json', __dir__)
    expect(Monadic::Help::Installation).to receive(:new).with(dump_path: host_dump)
    Monadic::Help.installation
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
    expect(Monadic::Help::Installation).to receive(:new).with(dump_path: '/monadic/help_data/help_db.json')
    Monadic::Help.installation
    ENV['HELP_DATA_DUMP'] = '/server/configured.json'
    expect(Monadic::Help::Installation).to receive(:new).with(dump_path: '/server/configured.json')
    Monadic::Help.installation
  ensure
    previous.nil? ? ENV.delete('HELP_DATA_DUMP') : ENV['HELP_DATA_DUMP'] = previous
  end

  it 'wires boot to the on-demand service and preserves the automatic Help greeting' do
    boot = File.read(File.expand_path('../../../lib/monadic.rb', __dir__))
    expect(boot).to include('require_relative "monadic/help"', 'register Monadic::Routes::HelpRoutes')
    expect(boot).not_to include('help_embeddings_loader', 'HELP_EMBEDDINGS_DB')
    mdsl = File.read(File.expand_path('../../../apps/monadic_help/monadic_help_openai.mdsl', __dir__))
    expect(mdsl).to include('initiate_from_assistant true')
  end
end
