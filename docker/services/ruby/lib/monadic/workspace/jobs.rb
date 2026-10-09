# frozen_string_literal: true

require_relative 'ids'
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
      # Returns { job_id:, path: } with the real local path.
      def create!(workspace_relative_dir)
        data_root = File.realpath(Monadic::Utils::Environment.data_path)
        artifacts = File.join(data_root, workspace_relative_dir, 'artifacts')
        # artifacts/ must be the real folder the ledger names, not a link
        # someone put in its place.
        unless File.directory?(artifacts) && File.realpath(artifacts) == artifacts
          raise Unavailable, "the chat's artifacts folder is missing or is not a plain folder"
        end

        job_id = Ids.generate(:job)
        path = File.join(artifacts, job_id)
        Dir.mkdir(path)
        { job_id: job_id, path: path }
      rescue SystemCallError => e
        raise Unavailable, "could not create a folder for this run (#{e.class.name.split('::').last})"
      end

      # Regular files directly in the job folder whose names match pattern,
      # never following links. Output is looked up here, not taken from the
      # tool's printed paths.
      def outputs(path, pattern)
        Dir.children(path).sort.filter_map do |name|
          next unless name.match?(pattern)

          file = File.join(path, name)
          file if File.file?(file) && !File.symlink?(file)
        end
      end
    end
  end
end
