# frozen_string_literal: true

require_relative '../workspace/ids'
require_relative '../workspace/chats'
require_relative '../workspace/folders'
require_relative '../workspace/jobs'
require_relative '../workspace/ledger'
require_relative '../utils/shared_path_guard'
require_relative '../shared_tools/workbench_tools'

module Monadic
  module Workbench
    # What a tool made for a chat (a diagram, a score, a sound, a video),
    # kept in a run folder of the chat's folder
    # (conversations/<folder>/artifacts/j_<id>/) and shown on the work
    # screen. The chat says only that it is there: the content is on the
    # work screen, and a line under the reply opens it again.
    module ChatOutput
      module_function

      # A run folder for one run of a tool: in the chat the reply was asked
      # in (workbench), or else the session's. nil without a chat or its
      # folder.
      def run_folder(session:, workbench:, app_name:)
        chat_id = workbench&.chat_id || (session && session[Monadic::Workspace::Chats::SESSION_KEY])
        return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        folder = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: app_name)
        return nil unless folder[:status] == :ready

        Monadic::Workspace::Jobs.create!(folder[:workspace_id])
      rescue Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Jobs::Unavailable,
             Monadic::Workspace::Ledger::Unreadable
        nil
      end

      # Writes bytes as a new file named name in the run folder (never over
      # a file). Returns its path in the shared folder.
      def keep(job, name, bytes)
        Monadic::Utils::SharedPathGuard.write_file!(File.join(job[:path], name), bytes, mode: 'wb', replace: false, strict: true)
        File.join(job[:relative], name)
      end

      # Shows a file of the shared folder on the work screen of the reply;
      # true when it is shown.
      def show(path, workbench)
        return false unless workbench

        MonadicSharedTools::WorkbenchTools.show_file(path, workbench).start_with?('{')
      end

      # Keeps files a tool made ({ name => bytes }, in that order) in a new
      # run folder of the chat and shows each on the work screen. Returns
      # { paths:, shown: } (shown: every file was shown), or nil without a
      # chat or its folder. A run folder left empty by a failure goes.
      def keep_and_show(session:, workbench:, app_name:, files:)
        job = run_folder(session: session, workbench: workbench, app_name: app_name)
        return nil unless job

        paths = files.map { |name, bytes| keep(job, name, bytes) }
        { paths: paths, shown: paths.map { |path| show(path, workbench) }.all? }
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        drop_if_empty(job)
        raise
      end

      # A run folder a failed run left empty goes; one with anything in it
      # stays.
      def drop_if_empty(job)
        Dir.rmdir(job[:path]) if job && Monadic::Workspace::Folders.real_path(job[:relative], :directory)
      rescue SystemCallError
        nil
      end

      # What the model is told of a file kept (and shown or not), for its
      # reply.
      def said(what, path, shown:)
        if shown
          "#{what} was saved as #{path} and is shown on the work screen beside the chat. In your reply, say so " \
            'in one short line with this path; do not put its content in the reply.'
        else
          "#{what} was saved as #{path}, but the work screen could not show it. Give the user this path."
        end
      end
    end
  end
end
