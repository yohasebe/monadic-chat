# frozen_string_literal: true

require_relative 'ids'
require_relative 'folders'
require_relative 'ledger'
require_relative 'ledger_schema'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workspace
    # A folder for one run of a tool on a chat's files:
    # <workspace>/artifacts/j_<id>/. Each run gets its own, so two analyses
    # in the same chat cannot overwrite each other's output, and what a run
    # produced is found by looking in its folder rather than by trusting
    # what the tool printed.
    module Jobs
      class Unavailable < StandardError; end

      module_function

      # A run folder in a chat's folder. The workspace is looked up in the
      # ledger, which gives the folder and the chat the run belongs to (a
      # caller does not say which chat). Returns { job_id:, path:, relative:,
      # owner: }: the real local path, the path under the shared folder, and
      # who the run belongs to, fixed when the run starts.
      def create!(workspace_id, ledger: Ledger.default)
        workspace = ledger.workspace(workspace_id)
        raise Unavailable, "the chat's folder is not in the ledger" unless workspace

        make(workspace[:relative_dir], kind: :chat, chat_id: workspace[:chat_id], workspace_id: workspace_id)
      end

      # A run folder outside any chat, for work asked for from outside the app
      # (the MCP server): <root>/artifacts/<job_id> in the shared folder, root
      # being one of LedgerSchema::OUTSIDE_ROOTS. Each level is made if
      # missing and checked to be a plain folder, as for chats.
      def create_outside_chat!(root)
        raise ArgumentError, "#{root.inspect} is not a folder for runs outside any chat" unless LedgerSchema::OUTSIDE_ROOTS.include?(root)

        data_root = File.realpath(Monadic::Utils::Environment.data_path)
        begin
          Monadic::Utils::SharedPathGuard.mkdir_p!(File.join(data_root, root, 'artifacts'), strict: true)
        rescue Monadic::Utils::SharedPathGuard::InvalidPath
          raise Unavailable, "#{root}/artifacts/ in the shared folder is not a plain folder"
        end
        make(root, kind: :outside, root: root)
      rescue SystemCallError => e
        raise Unavailable, "could not create a folder for this run (#{e.class.name.split('::').last})"
      end

      def make(base, **owner)
        relative = File.join(base, 'artifacts')
        # artifacts/ must be the real folder the ledger names, not a link
        # someone put in its place.
        artifacts = Folders.real_path(relative, :directory)
        raise Unavailable, "the chat's artifacts folder is missing or is not a plain folder" unless artifacts

        job_id = Ids.generate(:job)
        path = Monadic::Utils::SharedPathGuard.make_dir!(File.join(artifacts, job_id), strict: true)
        { job_id: job_id, path: path, relative: File.join(relative, job_id), owner: owner.freeze }
      rescue SystemCallError, Monadic::Utils::SharedPathGuard::InvalidPath => e
        raise Unavailable, "could not create a folder for this run (#{e.class.name.split('::').last})"
      end
      private_class_method :make

      # Regular files directly in the job folder whose names match pattern,
      # never following links. Output is looked up here, not taken from the
      # tool's printed paths.
      # The job folder is checked again here, when its output is taken: the
      # tool ran for minutes, and the folder (or one above it) may have been
      # swapped for a link to somewhere else in the meantime.
      def outputs(job, pattern)
        return [] unless Folders.real_path(job[:relative], :directory)

        Dir.children(job[:path]).sort.filter_map do |name|
          next unless name.match?(pattern)

          Folders.real_path(File.join(job[:relative], name))
        end
      end
    end
  end
end
