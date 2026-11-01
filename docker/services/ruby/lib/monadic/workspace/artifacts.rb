# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative 'ids'
require_relative 'ledger'
require_relative 'ledger_schema'
require_relative 'server_owner'

module Monadic
  module Workspace
    # What the server makes from a run (today the subtitles of a transcript),
    # kept where only the server can change it: the state folder, beside the
    # ledger, as state/artifacts/<artifact id>/<name>. The ledger records it
    # with the size and sha256 of the bytes the server wrote, so a copy made
    # later is checked against what was made, not against whatever the file
    # holds by then. The run folder in the shared folder gets a copy for
    # people and other programs to read; nothing trusts that copy.
    module Artifacts
      DIRNAME = 'artifacts'

      module_function

      # Writes body as an artifact of kind for the run job (Jobs.create!,
      # whose owner says whom the run belongs to) and records it. Returns the
      # record with the path of the kept file.
      #
      # Nothing is made while this ledger is no longer written (Unsettled) or
      # the server is stopping, and a server that stops waits for this to
      # finish. When the record cannot be made, the kept file is removed
      # (only this call made it, in a folder only the server writes); when
      # the record may have been saved but not settled (Unsettled), the file
      # is kept and nothing more is written.
      def store!(job:, kind:, body:, ledger: Ledger.default)
        name = LedgerSchema::ARTIFACT_KINDS.fetch(kind) { raise ArgumentError, "unknown kind #{kind}" }
        bytes = body.to_s.b.freeze
        sha256 = Digest::SHA256.hexdigest(bytes)

        ServerOwner.writing do
          raise Ledger::Unsettled, 'the ledger is no longer written; restart Monadic Chat' if Ledger.unsettled?(ledger.path)

          artifact_id = Ids.generate(:artifact)
          root = File.join(File.dirname(ledger.path), DIRNAME)
          dir = File.join(root, artifact_id)
          made_root = make_root(root)
          Dir.mkdir(dir, 0o700)
          begin
            Ledger::Disk.create_exclusive(File.join(dir, name), bytes)
            Ledger::Disk.sync_dir(dir)
            Ledger::Disk.sync_dir(root)
            # A root made just now is an entry of the state folder too
            Ledger::Disk.sync_dir(File.dirname(root)) if made_root
            record = ledger.register_artifact(artifact_id: artifact_id, owner: job.fetch(:owner), job_id: job.fetch(:job_id),
                                              kind: kind, size: bytes.bytesize, sha256: sha256)
          rescue Ledger::Unsettled
            raise
          rescue StandardError
            FileUtils.rm_rf(dir)
            raise
          end
          record.merge(path: File.join(dir, name))
        end
      end

      # Makes the folder of all kept artifacts; true when this call made it.
      def make_root(root)
        Dir.mkdir(root, 0o700)
        true
      rescue Errno::EEXIST
        raise Errno::ENOTDIR, root unless File.directory?(root) && !File.symlink?(root)

        false
      end
      private_class_method :make_root

      # Where an artifact recorded in this ledger is kept.
      def path(artifact_id, kind, ledger: Ledger.default)
        raise ArgumentError, 'invalid artifact id' unless Ids.valid?(:artifact, artifact_id)

        File.join(File.dirname(ledger.path), DIRNAME, artifact_id, LedgerSchema::ARTIFACT_KINDS.fetch(kind))
      end
    end
  end
end
