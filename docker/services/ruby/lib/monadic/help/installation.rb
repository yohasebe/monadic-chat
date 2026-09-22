# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'tempfile'
require 'time'
require_relative '../vector_store'
require_relative '../utils/environment'
require_relative 'validated_dump'

module Monadic
  module Help
    # Preparation API only: boot loading, routes and Help tools do not use it yet.
    # All processes targeting the same database must share coordination_dir.
    # Never unlink lock files: flock ownership is tied to the inode.
    class Installation
      COLLECTIONS = ValidatedDump::COLLECTIONS
      METADATA_KEY = 'monadic_help_installation'
      DEFAULT_DUMP = '/monadic/help_data/help_db.json'
      DEFAULT_TIMEOUT = 300
      class Failed < StandardError; end
      class Unavailable < StandardError
        attr_reader :status

        def initialize(status)
          @status = status
          super("Help database unavailable: #{status[:state]} (#{status[:reason]})")
        end
      end

      def self.default_coordination_dir
        base = if Monadic::Utils::Environment.in_container?
                 '/monadic/data'
               else
                 File.expand_path('~/monadic/data')
               end
        File.join(base, '.help-installation')
      end

      def initialize(store: VectorStore.default_backend,
                     dump_path: ENV.fetch('HELP_DATA_DUMP', DEFAULT_DUMP),
                     coordination_dir: self.class.default_coordination_dir,
                     batch_size: 256, job_timeout: DEFAULT_TIMEOUT,
                     connection_factory: nil)
        raise ArgumentError, 'batch_size must be positive' unless batch_size.is_a?(Integer) && batch_size.positive?
        raise ArgumentError, 'job_timeout must be positive' unless job_timeout.positive?

        @store, @dump_path, @directory = store, dump_path, coordination_dir
        @batch_size, @job_timeout = batch_size, job_timeout
        @connection_factory = connection_factory || lambda {
          require_relative '../utils/help_embeddings'
          HelpEmbeddings.new(vector_store: @store)
        }
      end

      # No filesystem or Qdrant writes/bootstrap.
      # A shared lock keeps the multi-request snapshot stable against installs.
      def status
        lock = open_lock('job', create: false)
        unless lock
          snapshot = database_status({})
          # The first installer always creates this file before touching Qdrant.
          # Once created, it is never unlinked. Retry if initialization raced us.
          return File.exist?(File.join(@directory, 'job.lock')) ? status : snapshot
        end
        return installing_status unless lock.flock(File::LOCK_SH | File::LOCK_NB)

        progress = read_progress
        if progress['state'] == 'running'
          progress = progress.merge('state' => 'failed', 'reason' => 'Installation interrupted before completion')
        end
        database_status(progress).merge(last_attempt: progress)
      ensure
        lock&.close
      end

      # Returns immediately; polling status works across processes and restarts.
      # Native thread keeps JSON validation and blocking I/O off Falcon's reactor.
      def start
        lock = open_lock('job')
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          lock.close
          # A status snapshot can also briefly own a shared job lock. Do not
          # claim that a job exists; the caller can retry this busy response.
          return { accepted: false, state: 'busy', retryable: true }
        end

        previous = read_progress
        progress = {
          'install_id' => SecureRandom.uuid, 'state' => 'running',
          'stage' => 'validating', 'processed' => 0, 'total' => nil,
          'database_invalid' => previous['database_invalid'] == true,
          'started_at' => Time.now.utc.iso8601
        }
        write_progress(progress)
        @worker = Thread.new { run_install(lock, progress) }
        { accepted: true, state: 'installing', install_id: progress['install_id'] }
      rescue StandardError
        lock&.close unless lock&.closed?
        raise
      end

      # CLI/tests only; HTTP handlers should poll status, never join a worker.
      def wait
        @worker&.join
        status
      end

      # Hold this lease for the ENTIRE help read (items plus parent docs).
      # Connection creation is independent of availability and never caches nil.
      # Callers must not retain the yielded connection outside this block.
      def with_search
        lease = open_lock('readers')
        unless lease.flock(File::LOCK_SH | File::LOCK_NB)
          raise Unavailable, installing_status
        end
        job = open_lock('job')
        idle = job.flock(File::LOCK_SH | File::LOCK_NB)
        progress = read_progress
        # Validation does not invalidate an existing database. Preparing closes
        # admission before the installer waits for leases already in flight.
        if !idle && progress['stage'] != 'validating'
          raise Unavailable, installing_status
        end
        current = database_status(progress)
        raise Unavailable, current unless current[:searchable]

        job.close
        yield @connection_factory.call
      ensure
        job&.close unless job&.closed?
        lease&.close
      end

      private

      def open_lock(name, create: true)
        FileUtils.mkdir_p(@directory) if create
        mode = create ? File::RDWR | File::CREAT : File::RDONLY
        File.open(File.join(@directory, "#{name}.lock"), mode, 0o600)
      rescue Errno::ENOENT
        raise if create

        nil
      end

      def read_progress
        data = JSON.parse(File.read(File.join(@directory, 'progress.json')))
        raise JSON::ParserError, 'Invalid progress record' unless data.is_a?(Hash)

        data
      rescue Errno::ENOENT
        {}
      rescue JSON::ParserError
        { 'state' => 'failed', 'database_invalid' => true, 'reason' => 'Corrupt installation journal' }
      end

      def write_progress(progress)
        Tempfile.create(['progress-', '.json'], @directory) do |file|
          file.write(JSON.generate(progress))
          file.flush
          file.fsync
          File.rename(file.path, File.join(@directory, 'progress.json'))
        end
        # Persist the rename before a destructive database operation.
        File.open(@directory, File::RDONLY) { |dir| dir.fsync }
      end

      def installing_status
        { state: 'installing', searchable: false, progress: read_progress }
      end

      def result(state, reason: nil, **extra)
        { state: state, searchable: %w[installed update_available].include?(state), reason: reason }.merge(extra)
      end

      def database_status(progress)
        # Fetch BOTH before classifying, so a missing first collection cannot
        # hide a connection failure on the second one.
        metadata = COLLECTIONS.map { |name| @store.collection_metadata(name: name) }
        if progress['database_invalid']
          return result('failed', reason: progress['reason'] || 'Installation interrupted before verification', progress: progress)
        end
        if metadata.all?(&:nil?)
          return result('failed', reason: progress['reason'] || 'Installation interrupted', progress: progress) if %w[failed running].include?(progress['state'])

          return result('not_installed')
        end
        return result('failed', reason: 'Missing help collection') if metadata.any?(&:nil?)

        records = metadata.map { |m| m[METADATA_KEY] }
        return result('legacy', reason: 'No installation records') if records.all?(&:nil?)

        verify_records!(records)
        verify_counts!(records.first)
        bundled_hash, bundled_error = bundled_fingerprint
        matches = bundled_hash ? records.first['dump_sha256'] == bundled_hash : nil
        result(matches == false ? 'update_available' : 'installed',
               installation: records.first, bundled_match: matches, bundled_error: bundled_error,
               last_attempt: progress)
      rescue VectorStore::BackendError, HTTP::Error => e
        result('unavailable', reason: e.message)
      rescue Failed => e
        result('failed', reason: e.message)
      end

      def verify_records!(records)
        keys = %w[install_id dump_sha256 dump_version embedding_model embedding_dimension expected_docs expected_items state loaded_at]
        valid = records.all? do |r|
          r.is_a?(Hash) && keys.all? { |key| r.key?(key) } &&
            r['install_id'].is_a?(String) && !r['install_id'].empty? &&
            r['dump_sha256'].is_a?(String) && r['dump_sha256'].match?(/\A[0-9a-f]{64}\z/) &&
            r['dump_version'] == ValidatedDump::VERSION && r['embedding_model'] == ValidatedDump::MODEL &&
            r['embedding_dimension'] == ValidatedDump::DIMENSION && r['state'] == 'completed' &&
            %w[expected_docs expected_items].all? { |k| r[k].is_a?(Integer) && r[k].positive? } &&
            r['loaded_at'].is_a?(String) && !r['loaded_at'].empty?
        end
        raise Failed, 'Missing, incomplete or incompatible installation records' unless valid
        raise Failed, 'Installation records disagree' unless keys.all? { |key| records[0][key] == records[1][key] }
      end

      def verify_counts!(record)
        COLLECTIONS.zip(%w[expected_docs expected_items]).each do |name, key|
          count = @store.count(collection: name, exact: true)
          raise Failed, "Point count mismatch for #{name}: #{count} != #{record[key]}" unless count == record[key]
        end
      end

      def bundled_fingerprint
        stat = File.stat(@dump_path)
        signature = [stat.ino, stat.size, stat.mtime, stat.ctime]
        if @fingerprint_signature != signature
          @fingerprint = Digest::SHA256.file(@dump_path).hexdigest
          @fingerprint_signature = signature
        end
        [@fingerprint, nil]
      rescue SystemCallError => e
        [nil, e.message]
      end

      def checkpoint!(deadline)
        raise Failed, 'Installation time limit exceeded' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end

      def run_install(lock, progress)
        Thread.current.report_on_exception = false
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @job_timeout
        dump = ValidatedDump.new(@dump_path)
        checkpoint!(deadline)
        record = dump.record(progress['install_id'])
        progress.merge!('stage' => 'preparing', 'total' => record['expected_docs'] + record['expected_items'])
        write_progress(progress)
        readers = open_lock('readers')
        until readers.flock(File::LOCK_EX | File::LOCK_NB)
          checkpoint!(deadline)
          sleep 0.05
        end
        checkpoint!(deadline)
        # Durable invalidation also covers a crash before the first DELETE or
        # after both completion PATCHes but before their final verification.
        progress['database_invalid'] = true
        write_progress(progress)
        COLLECTIONS.each do |name|
          checkpoint!(deadline)
          @store.delete_collection(name: name)
          checkpoint!(deadline)
          definition = VectorStore::Schema::DEFINITIONS.fetch(name)
          @store.create_collection(name: name, **definition)
          checkpoint!(deadline)
          @store.update_collection_metadata(name: name, metadata: { METADATA_KEY => record })
        end
        progress['stage'] = 'loading'
        write_progress(progress)
        COLLECTIONS.each do |name|
          dump.points(name).each_slice(@batch_size) do |batch|
            checkpoint!(deadline)
            points = batch.map { |p| { id: p.fetch('id'), vector: p.fetch('vector'), payload: p.fetch('payload') } }
            response = @store.upsert_points(collection: name, points: points)
            raise Failed, "Upsert not completed for #{name}" unless response.is_a?(Hash) && response['status'] == 'completed'

            progress['processed'] += points.size
            write_progress(progress)
          end
        end
        progress['stage'] = 'verifying'
        write_progress(progress)
        checkpoint!(deadline)
        verify_counts!(record)
        record = record.merge('state' => 'completed', 'loaded_at' => Time.now.utc.iso8601)
        COLLECTIONS.each do |name|
          checkpoint!(deadline)
          @store.update_collection_metadata(name: name, metadata: { METADATA_KEY => record })
        end
        records = COLLECTIONS.map { |name| @store.collection_metadata(name: name)&.fetch(METADATA_KEY, nil) }
        verify_records!(records)
        raise Failed, 'Completion record was not persisted' unless records.all? { |r| r == record }

        verify_counts!(record)
        checkpoint!(deadline)
        progress.merge!('state' => 'completed', 'stage' => 'completed', 'database_invalid' => false)
        write_progress(progress)
      rescue StandardError => e
        progress.merge!('state' => 'failed', 'reason' => "#{e.class}: #{e.message}")
        write_progress(progress)
      ensure
        readers&.close
        lock.close
      end
    end
  end
end
