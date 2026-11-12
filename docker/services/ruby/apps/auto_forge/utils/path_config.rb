# frozen_string_literal: true

require 'fileutils'
require_relative '../../../lib/monadic/utils/shared_path_guard'
require_relative '../../../lib/monadic/workspace/chat_context'
require_relative '../../../lib/monadic/workspace/folders'
require_relative '../../../lib/monadic/workspace/request_context'
require_relative '../../../lib/monadic/workbench/made'

module AutoForge
  module Utils
    # Where AutoForge keeps its projects: the auto_forge folder of the chat
    # the reply runs for (<chat folder>/auto_forge/<Project>_<time>/). The
    # turn that makes a project records it as made (Workbench::Made), so
    # deleting that turn moves the project to the chat's trash; a turn that
    # changes a project keeps it as it was first (Workbench::Revision), so
    # deleting that turn puts it back.
    module PathConfig
      extend self

      DIRNAME = 'auto_forge'

      class NoChat < StandardError; end

      # Get the base data directory based on environment
      # @return [String] Base data directory path
      def base_data_path
        Monadic::Utils::Environment.data_path
      end

      # The chat the reply runs for, { id:, epoch: }, or nil.
      def current_chat
        Monadic::Workspace::ChatContext.work_chat(nil)
      end

      # The chat's folder (relative to the shared folder). NoChat without a
      # chat or its folder.
      def chat_folder
        chat = current_chat
        raise NoChat, 'AutoForge keeps its projects in the folder of a chat; there is no chat now' unless chat

        folder = Monadic::Workspace::Folders.ensure_for_chat!(chat[:id], app_name: 'AutoForge')
        raise NoChat, "the chat's folder is missing" unless folder[:status] == :ready

        folder[:relative_dir]
      rescue Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Ledger::Unreadable => e
        raise NoChat, e.message
      end

      # The folder of the chat's projects.
      # @return [String] AutoForge project directory path
      def project_base_path
        File.join(base_data_path, chat_folder, DIRNAME)
      end

      # Get backup directory path
      # @return [String] Backup directory path
      def backup_directory_path
        File.join(project_base_path, ".backups")
      end

      # Check if path is within safe boundaries
      # @param path [String] Path to check
      # @return [Boolean] True if path is safe
      def safe_path?(path)
        expanded_path = File.expand_path(path)
        expanded_path.start_with?(base_data_path)
      end

      # The path of full_path in the shared folder, or nil when it is not in
      # it.
      def shared_relative(full_path)
        root = File.realpath(base_data_path)
        real = File.realpath(full_path)
        real.start_with?("#{root}/") ? real.delete_prefix("#{root}/") : nil
      rescue SystemCallError
        nil
      end

      # The project at project_path was made by the running reply.
      def record_made(project_path)
        relative = shared_relative(project_path)
        request = Monadic::Workspace::RequestContext.current
        return unless relative && request

        Monadic::Workbench::Made.add(request.request_id, relative, chat_id: current_chat&.dig(:id))
      end

      # The running reply is about to change the project at project_path:
      # it is kept as it is first, once per reply (Workbench::Revision).
      def before_change(project_path)
        relative = shared_relative(project_path)
        request = Monadic::Workspace::RequestContext.current
        chat = current_chat
        return unless relative && request && chat

        Monadic::Workbench::Revision.keep!(request.request_id, relative, chat_id: chat[:id])
      end
    end
  end
end
