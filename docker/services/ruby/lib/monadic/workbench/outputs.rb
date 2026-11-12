# frozen_string_literal: true

require_relative '../workspace/folders'
require_relative 'made'

module Monadic
  module Workbench
    # What a chat has made, for whichever app the chat is in now. The record
    # is each reply's own (its message keeps the paths it made,
    # "workbench_made"), so editing or deleting a turn changes it with the
    # turn and nothing else is kept in step.
    module Outputs
      module_function

      # At most this many files are listed for one folder made, and this
      # deep: a folder with more (a project) is listed as itself.
      FILES_PER_FOLDER = 20
      DEPTH = 2

      # The chat's made files, oldest first: [{ path:, turn: }] (turn: the
      # number of the reply among the chat's replies). Only what is there
      # now; a folder made is listed by its files.
      def in_chat(session)
        messages = session.is_a?(Hash) ? Array(session[:messages]) : []
        turn = 0
        messages.flat_map do |message|
          next [] unless message.is_a?(Hash) && message['role'] == 'assistant'

          turn += 1
          Array(Made.clean(message['workbench_made'])).flat_map do |path|
            files_of(path).map { |file| { path: file, turn: turn } }
          end
        end.uniq { |entry| entry[:path] }
      end

      # The files a made path stands for: itself, or the files of a folder
      # (to DEPTH levels, FILES_PER_FOLDER at most). Nothing that is not
      # there or is reached through a link.
      def files_of(path)
        return [path] if Monadic::Workspace::Folders.real_path(path)
        return [] unless Monadic::Workspace::Folders.real_path(path, :directory)

        found = walk(path, DEPTH)
        found.size > FILES_PER_FOLDER ? [path] : found
      end

      def walk(path, depth)
        names = Dir.children(File.join(Monadic::Utils::Environment.data_path, path)).reject { |n| n.start_with?('.') }.sort
        names.flat_map do |name|
          child = File.join(path, name)
          if Monadic::Workspace::Folders.real_path(child)
            [child]
          elsif Monadic::Workspace::Folders.real_path(child, :directory)
            depth.positive? ? walk(child, depth - 1) : [child]
          else
            []
          end
        end
      rescue SystemCallError
        []
      end
    end
  end
end
