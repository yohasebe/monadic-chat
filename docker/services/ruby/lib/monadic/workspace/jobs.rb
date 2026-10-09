# frozen_string_literal: true

require_relative 'ids'
require_relative 'folders'
require_relative '../utils/environment'

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

      # workspace_relative_dir is the ledger's relative folder of the chat.
      # Returns { job_id:, path:, relative: }: the real local path and the
      # path under the shared folder.
      def create!(workspace_relative_dir)
        relative = File.join(workspace_relative_dir, 'artifacts')
        # artifacts/ must be the real folder the ledger names, not a link
        # someone put in its place.
        artifacts = Folders.real_path(relative, :directory)
        raise Unavailable, "the chat's artifacts folder is missing or is not a plain folder" unless artifacts

        job_id = Ids.generate(:job)
        path = File.join(artifacts, job_id)
        Dir.mkdir(path)
        { job_id: job_id, path: path, relative: File.join(relative, job_id) }
      rescue SystemCallError => e
        raise Unavailable, "could not create a folder for this run (#{e.class.name.split('::').last})"
      end

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
