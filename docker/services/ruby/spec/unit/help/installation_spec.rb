# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'timeout'
require 'monadic/help/installation'
require_relative '../../../apps/monadic_help/monadic_help_tools'

RSpec.describe Monadic::Help::Installation do
  # A stateful store double: failures can occur before or after a durable write.
  class HelpInstallationStoreDouble
    attr_reader :collections, :operations
    attr_accessor :hook, :offline, :upsert_status

    def initialize
      @collections, @operations = {}, []
      @upsert_status = 'completed'
    end

    def event(action, name)
      raise Monadic::VectorStore::BackendError, 'offline' if offline

      @operations << [action, name]
      hook&.call(action, name)
    end

    def collection_metadata(name:)
      event(:metadata, name)
      copy(collections[name]&.fetch(:metadata))
    end

    def update_collection_metadata(name:, metadata:)
      event(:update_metadata, name)
      collections.fetch(name)[:metadata].merge!(copy(metadata))
      event(:updated_metadata, name)
      true
    end

    def create_collection(name:, **_definition)
      event(:create, name)
      collections[name] = { metadata: {}, points: {} }
      true
    end

    def delete_collection(name:)
      event(:delete, name)
      collections.delete(name)
      true
    end

    def upsert_points(collection:, points:)
      event(:upsert, collection)
      points.each { |p| collections.fetch(collection)[:points][p[:id]] = copy(p) }
      event(:upserted, collection)
      { 'status' => upsert_status }
    end

    def count(collection:, exact:)
      raise 'Expected exact count' unless exact == true

      event(:count, collection)
      collections.fetch(collection)[:points].size
    end

    def copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  around do |example|
    Dir.mktmpdir('help-install-spec') do |dir|
      @directory = dir
      @path = File.join(dir, 'help.json')
      @locks = File.join(dir, 'coordination')
      @services = []
      write_dump
      begin
        example.run
      ensure
        @services.each { |s| s.instance_variable_get(:@worker)&.join(3) }
      end
    end
  end

  let(:store) { HelpInstallationStoreDouble.new }
  let(:service) { new_service }
  let(:metadata_key) { described_class::METADATA_KEY }

  def new_service(**options)
    instance = described_class.new(store: store, dump_path: @path, coordination_dir: @locks,
                                   batch_size: 1, connection_factory: -> { store }, **options)
    @services << instance
    instance
  end

  def write_dump
    point = { 'id' => 1, 'vector' => { 'content' => [0.1] * 768 }, 'payload' => { 'is_internal' => false } }
    @data = {
      'version' => '1', 'embedding_model' => Monadic::Help::ValidatedDump::MODEL, 'embedding_dimension' => 768,
      'collections' => {
        'help_docs' => { 'points' => [point, point.merge('id' => 2)] },
        'help_items' => { 'points' => [1, 2, 3].map { |id| point.merge('id' => id, 'payload' => { 'is_internal' => false, 'doc_id' => 1 }) } }
      }
    }
    File.write(@path, JSON.generate(@data))
  end

  def install
    expect(service.start[:accepted]).to be true
    service.wait
  end

  def journal
    JSON.parse(File.read(File.join(@locks, 'progress.json')))
  end

  def write_journal(data)
    File.write(File.join(@locks, 'progress.json'), JSON.generate(data))
  end

  def await(queue)
    Timeout.timeout(5) { queue.pop }
  end

  it 'reports new and legacy databases without bootstrapping or mutating Qdrant' do
    expect(service.status[:state]).to eq('not_installed')
    expect(File.exist?(@locks)).to be false
    %w[help_docs help_items].each { |name| store.create_collection(name: name) }
    store.operations.clear
    expect(service.status).to include(state: 'legacy', searchable: false)
    expect(store.operations.map(&:first).uniq).to eq([:metadata])
  end

  it 'installs both collections, then permits reads immediately through a new service instance' do
    expect { service.with_search { raise 'should not run' } }.to raise_error(described_class::Unavailable)
    expect(install).to include(state: 'installed', searchable: true, bundled_match: true)
    expect(new_service.with_search { |connection| connection }).to equal(store)
    records = %w[help_docs help_items].map { |name| store.collections[name][:metadata][metadata_key] }
    expect(records[0]).to eq(records[1])
    expect(records[0]).to include('state' => 'completed', 'expected_docs' => 2, 'expected_items' => 3)
    expect(journal).to include('stage' => 'completed', 'processed' => 5, 'total' => 5)
  end

  it 'recognizes a changed bundled hash while allowing the complete public installed version' do
    install
    File.open(@path, 'a') { |f| f.write("\n") }
    expect(service.status).to include(state: 'update_available', searchable: true, bundled_match: false)
  end

  it 'makes the same Help tool host usable immediately after an explicit installation' do
    host = Object.new.extend(MonadicHelpTools)
    allow(Monadic::Help).to receive(:installation).and_return(service)
    expect(host.list_help_sections).to include(state: 'not_installed', code: 'help_database_unavailable')
    expect(store.collections).to be_empty
    expect(store.operations.map(&:first).uniq).to eq([:metadata])
    expect(install).to include(state: 'installed', searchable: true)
    expect(store).to receive(:list_titles).with(language: nil, include_internal: false).and_return([])
    expect(host.list_help_sections(include_internal: false)).to eq(sections: [])
    expect(host.instance_variables).to be_empty
  end

  it 'rehashes the validated install bytes instead of reusing the status hash' do
    install
    previous = service.status[:installation]['dump_sha256']
    File.open(@path, 'a') { |f| f.write("\n") }
    expect(install[:installation]['dump_sha256']).not_to eq(previous)
    expect(service.status[:bundled_match]).to be true
  end

  it 'does not confuse connection failure with absence or update availability' do
    store.offline = true
    expect(service.status).to include(state: 'unavailable', searchable: false)
    store.offline = false
    store.hook = ->(action, name) { raise Monadic::VectorStore::BackendError, 'offline' if action == :metadata && name == 'help_items' }
    expect(service.status[:state]).to eq('unavailable')
  end

  %w[help_docs help_items].each do |name|
    it "rejects missing #{name}, even with a completed peer" do
      install
      store.collections.delete(name)
      expect(new_service.status).to include(state: 'failed', searchable: false)
    end

    it "rejects an incorrect exact count in #{name}" do
      install
      store.collections[name][:points].delete(1)
      expect(service.status[:reason]).to match(/count mismatch/)
    end

    it "rejects an incomplete #{name} upsert before writing completion records" do
      store.hook = lambda do |action, collection|
        # The upsert still reports completed, but one point is not retained.
        store.collections[name][:points].delete(1) if action == :upserted && collection == name
      end

      result = install
      expected = @data['collections'][name]['points'].size
      aggregate_failures do
        expect(journal).to include(
          'state' => 'failed', 'stage' => 'verifying', 'database_invalid' => true,
          'reason' => "#{described_class::Failed}: Point count mismatch for #{name}: #{expected - 1} != #{expected}"
        )
        %w[help_docs help_items].each do |collection|
          expect(store.collections[collection][:metadata][metadata_key]['state']).to eq('installing')
          expect(store.operations.count([:update_metadata, collection])).to eq(1)
        end
        expect(result).to include(state: 'failed', searchable: false)
        expect(new_service.status).to include(state: 'failed', searchable: false)
      end
    end

    it "rejects lost #{name} points after writing completion records" do
      store.hook = lambda do |action, collection|
        # Lose a point only after the last completion record has been persisted.
        if action == :updated_metadata && collection == 'help_items' &&
           store.collections[collection][:metadata][metadata_key]['state'] == 'completed'
          store.collections[name][:points].delete(1)
        end
      end

      result = install
      expected = @data['collections'][name]['points'].size
      aggregate_failures do
        %w[help_docs help_items].each do |collection|
          expect(store.collections[collection][:metadata][metadata_key]['state']).to eq('completed')
        end
        expect(journal).to include(
          'state' => 'failed', 'stage' => 'verifying', 'database_invalid' => true,
          'reason' => "#{described_class::Failed}: Point count mismatch for #{name}: #{expected - 1} != #{expected}"
        )
        expect(result).to include(state: 'failed', searchable: false)
        expect(new_service.status).to include(state: 'failed', searchable: false)
      end
    end

    %w[install_id dump_sha256 expected_docs loaded_at].each do |field|
      it "rejects mismatched #{field} in #{name}" do
        install
        store.collections[name][:metadata][metadata_key][field] = 'mismatch'
        expect(service.status).to include(state: 'failed', searchable: false)
      end
    end

    [1, 2].each do |batch|
      it "recovers from #{name} batch #{batch} failure after restarting the service" do
        calls = 0
        store.hook = lambda do |action, collection|
          next unless action == :upserted && collection == name
          calls += 1
          raise 'injected batch failure' if calls == batch
        end
        expect(install[:state]).to eq('failed')
        expect(new_service.status).to include(state: 'failed', searchable: false)
        expect(new_service.status[:reason]).to match(/injected batch failure/)
        store.hook = nil
        expect(install[:state]).to eq('installed')
      end
    end
  end

  it 'requires completed upserts even if the exact count already matches' do
    store.upsert_status = 'acknowledged'
    expect(install[:state]).to eq('failed')
    expect(service.status[:reason]).to match(/Upsert not completed/)
  end

  it 'rejects incomplete or missing completion records with no local journal' do
    install
    write_journal({})
    store.collections['help_items'][:metadata][metadata_key]['state'] = 'installing'
    expect(new_service.status[:state]).to eq('failed')
    store.collections['help_items'][:metadata].clear
    expect(new_service.status[:state]).to eq('failed')
  end

  [:delete, :create].each do |action|
    it "handles abrupt termination at the first #{action} without reporting installing forever" do
      install
      store.hook = ->(operation, _) { Thread.exit if operation == action }
      service.start
      expect(service.wait[:state]).to eq('failed')
      expect(new_service.status[:reason]).to match(/interrupted/)
    end
  end

  %w[help_docs help_items].each do |name|
    it "handles abrupt termination after the completed #{name} record is written" do
      store.hook = lambda do |action, collection|
        if action == :updated_metadata && collection == name &&
           store.collections[name][:metadata][metadata_key]['state'] == 'completed'
          Thread.exit
        end
      end
      service.start
      expect(service.wait).to include(state: 'failed', searchable: false)
      expect(new_service.status[:state]).to eq('failed')
    end
  end

  it 'does not open search when read-back of a completion record fails' do
    store.hook = lambda do |action, _|
      if action == :metadata && journal['stage'] == 'verifying'
        raise Monadic::VectorStore::BackendError, 'verification lost'
      end
    end
    service.start
    expect(service.wait[:state]).to eq('unavailable')
    store.hook = nil
    expect(new_service.status[:state]).to eq('failed')
  end

  it 'recovers as installed after the verified completion journal is durable' do
    allow(service).to receive(:write_progress).and_wrap_original do |original, progress|
      original.call(progress)
      Thread.exit if progress['state'] == 'completed'
    end
    service.start
    expect(service.wait).to include(state: 'installed', searchable: true)
    expect(new_service.with_search { :available }).to eq(:available)
  end

  it 'preserves a healthy database when validation is interrupted' do
    install
    before = store.copy(store.collections)
    allow(Monadic::Help::ValidatedDump).to receive(:new) { Thread.exit }
    service.start
    expect(service.wait).to include(state: 'installed', searchable: true)
    expect(new_service.status.dig(:last_attempt, 'reason')).to match(/interrupted/)
    expect(store.collections).to eq(before)
  end

  it 'allows existing public data to be searched while validation runs' do
    install
    entered, release = Queue.new, Queue.new
    allow(Monadic::Help::ValidatedDump).to receive(:new).and_wrap_original do |original, path|
      entered << true
      release.pop
      original.call(path)
    end
    service.start
    await(entered)
    expect(new_service.status.dig(:progress, 'stage')).to eq('validating')
    expect(new_service.with_search { :available }).to eq(:available)
    release << true
    expect(service.wait[:state]).to eq('installed')
  ensure
    release << true if release
  end

  it 'leaves failed verification unavailable even if a later retry also fails validation' do
    install
    write_journal(journal.merge('database_invalid' => true, 'state' => 'running', 'stage' => 'verifying'))
    File.write(@path, '{}')
    expect(install[:state]).to eq('failed')
    expect { new_service.with_search { :invalid } }.to raise_error(described_class::Unavailable)
  end

  it 'reports count-read transport failures as unavailable instead of corruption' do
    install
    store.hook = ->(action, _) { raise Monadic::VectorStore::BackendError, 'count offline' if action == :count }
    expect(service.status).to include(state: 'unavailable', reason: 'count offline')
  end

  it 'does not mark matching but invalid completion records as installed' do
    install
    %w[help_docs help_items].each do |name|
      store.collections[name][:metadata][metadata_key]['embedding_model'] = 'incompatible'
    end
    expect(service.status[:state]).to eq('failed')
  end

  it 'reports a corrupt journal as failed without rewriting it during status reads' do
    install
    path = File.join(@locks, 'progress.json')
    File.write(path, '{')
    expect(new_service.status).to include(state: 'failed', reason: 'Corrupt installation journal')
    expect(File.read(path)).to eq('{')
  end

  it 'keeps a healthy database intact on invalid preflight or missing source, across retries' do
    install
    before = store.copy(store.collections)
    File.write(@path, '{}')
    expect(install).to include(searchable: true)
    expect(store.collections).to eq(before)
    expect(journal['reason']).to match(/Unsupported dump version/)
    # Rename the fixture to simulate missing media without deleting a file.
    File.rename(@path, "#{@path}.missing")
    expect(install).to include(state: 'installed', searchable: true, bundled_match: nil)
    expect(service.status[:bundled_error]).to match(/No such file/)
    expect(store.collections).to eq(before)
  end

  it 'exposes preflight failure details while retaining the legacy database state' do
    %w[help_docs help_items].each { |name| store.create_collection(name: name) }
    before = store.copy(store.collections)
    File.write(@path, '{}')
    expect(install[:state]).to eq('legacy')
    expect(new_service.status.dig(:last_attempt, 'reason')).to match(/Unsupported dump version/)
    expect(store.collections).to eq(before)
  end

  it 'does not erase an earlier interrupted-install marker on a failed validation retry' do
    install
    write_journal(journal.merge('state' => 'running', 'database_invalid' => true))
    File.write(@path, '{}')
    expect(install[:state]).to eq('failed')
  end

  it 'replaces deleted docs and internal points without changing any Library/PDF collection' do
    names = Monadic::VectorStore::Schema::ALL_COLLECTIONS
    names.each do |name|
      store.create_collection(name: name)
      store.collections[name][:points][99] = { id: 99, payload: { 'is_internal' => true } }
    end
    others = names - %w[help_docs help_items]
    before = store.copy(store.collections.slice(*others))
    store.operations.clear
    expect(install[:state]).to eq('installed')
    expect(store.collections.slice(*others)).to eq(before)
    expect(store.operations.map(&:last).uniq.sort).to eq(%w[help_docs help_items])
    expect(store.collections['help_docs'][:points].keys).to eq([1, 2])
    expect(store.collections['help_items'][:points].keys).to eq([1, 2, 3])
  end

  it 'rejects a foreign collection before deleting or upserting anything' do
    @data['collections']['pdf_docs'] = @data['collections']['help_docs']
    File.write(@path, JSON.generate(@data))
    expect(install[:state]).to eq('failed')
    expect(store.operations.map(&:first).uniq).to eq([:metadata])
  end

  it 'reports progress, rejects duplicate starts and closes admission while draining existing reads' do
    install
    entered, release = Queue.new, Queue.new
    reader = Thread.new { new_service.with_search { entered << true; release.pop } }
    await(entered)
    writes = Queue.new
    store.hook = ->(action, name) { writes << [action, name] if action == :delete }
    expect(service.start[:accepted]).to be true
    Timeout.timeout(5) { sleep 0.01 until new_service.status.dig(:progress, 'stage') == 'preparing' }
    expect(new_service.start).to include(accepted: false, state: 'busy', retryable: true)
    expect(writes).to be_empty
    expect { new_service.with_search { raise 'must not enter' } }.to raise_error(described_class::Unavailable)
    release << true
    reader.join
    expect(service.wait[:state]).to eq('installed')
    expect(await(writes).first).to eq(:delete)
  ensure
    release << true if release
    reader&.join(3)
  end

  it 'reports processed counts during each collection batch and rechecks both records before opening' do
    stages = []
    store.hook = lambda do |action, _|
      stages << journal.dup if [:upsert, :count, :metadata].include?(action) && File.exist?(File.join(@locks, 'progress.json'))
    end
    install
    loading = stages.select { |p| p['stage'] == 'loading' }
    expect(loading.map { |p| p['processed'] }).to eq([0, 1, 2, 3, 4])
    expect(stages.any? { |p| p['stage'] == 'verifying' && p['processed'] == 5 }).to be true
  end

  it 'shares the installation lock with a separate Ruby process and releases it on exit' do
    FileUtils.mkdir_p(@locks)
    File.write(File.join(@locks, 'job.lock'), '')
    ready_reader, ready_writer = IO.pipe
    release_reader, release_writer = IO.pipe
    child = fork do
      ready_reader.close
      release_writer.close
      File.open(File.join(@locks, 'job.lock'), 'r+') do |lock|
        lock.flock(File::LOCK_EX)
        ready_writer.write('1')
        ready_writer.close
        release_reader.read(1)
      end
      exit! 0
    end
    ready_writer.close
    release_reader.close
    Timeout.timeout(5) { ready_reader.read(1) }
    expect(service.start[:accepted]).to be false
    expect(service.status[:state]).to eq('installing')
    release_writer.write('1')
    Process.wait(child)
    child = nil
    expect(install[:state]).to eq('installed')
  ensure
    [ready_reader, ready_writer, release_reader, release_writer].compact.each { |io| io.close unless io.closed? }
    Process.wait(child) if child
  end

  it 'bounds the drain wait without destroying a healthy database' do
    install
    File.open(File.join(@locks, 'readers.lock'), 'r+') do |lease|
      lease.flock(File::LOCK_SH)
      worker = new_service(job_timeout: 0.05)
      worker.start
      expect(worker.wait[:searchable]).to be true
      expect(journal['reason']).to match(/time limit/)
    end
  end

  it 'waits for a search lease held by a separate process' do
    install
    ready_reader, ready_writer = IO.pipe
    release_reader, release_writer = IO.pipe
    child = fork do
      ready_reader.close
      release_writer.close
      new_service.with_search do
        ready_writer.write('1')
        ready_writer.close
        release_reader.read(1)
      end
      exit! 0
    end
    ready_writer.close
    release_reader.close
    Timeout.timeout(5) { ready_reader.read(1) }
    store.operations.clear
    service.start
    Timeout.timeout(5) { sleep 0.01 until new_service.status.dig(:progress, 'stage') == 'preparing' }
    expect(store.operations).not_to include([:delete, 'help_docs'])
    release_writer.write('1')
    Process.wait(child)
    child = nil
    expect(service.wait[:state]).to eq('installed')
  ensure
    [ready_reader, ready_writer, release_reader, release_writer].compact.each { |io| io.close unless io.closed? }
    Process.wait(child) if child
  end
end
