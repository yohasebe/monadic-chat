# frozen_string_literal: true

# Shared file operations tools for Monadic Chat applications.
#
# The files a model writes go into its chat's work/ folder
# (Monadic::Workspace::ChatFiles decides where); reads and listings may also
# reach the user's own files in the shared folder, never another chat's
# folder. Every result gives the path the file is at, so the next call (and
# code the model runs) uses that path.

require 'fileutils'
require_relative '../utils/shared_path_guard'
require_relative '../workspace/chat_files'

module MonadicSharedTools
  module FileOperations
    include MonadicHelper

    CHAT_FILES = Monadic::Workspace::ChatFiles

    # Read a file: one of this chat's (work/, inputs/, ...) or one the user
    # put in the shared folder outside conversations/. No link is followed
    # on the way, so none can lead into another chat's folder.
    def read_file_from_shared_folder(filepath:, workbench: nil)
      place = CHAT_FILES.for_read(filepath, caller: workbench, app_name: file_tools_app_name(workbench))
      content, stat = Monadic::Utils::SharedPathGuard.read_file!(place.full, strict: true) do |f|
        [f.read.force_encoding("UTF-8"), f.stat]
      end
      {
        success: true,
        filepath: place.relative,
        execution_path: place.container_path,
        content: content,
        metadata: {
          size: stat.size,
          modified_at: stat.mtime.iso8601,
          created_at: stat.ctime.iso8601,
          lines: content.lines.count
        }
      }
    rescue CHAT_FILES::Refused => e
      { success: false, error: e.message, filepath: filepath }
    rescue Monadic::Utils::SharedPathGuard::InvalidPath, Errno::ENOENT, Errno::EISDIR, Errno::ENOTDIR
      { success: false, error: "File not found", filepath: filepath }
    rescue Errno::EACCES
      { success: false, error: "Permission denied", filepath: filepath }
    rescue StandardError => e
      { success: false, error: "Error reading file: #{e.class.name.split('::').last}", filepath: filepath }
    end

    # Write or append to a file of this chat. A path outside the chat's
    # work/ folder is placed there under the same relative name; the result
    # says where (saved_as) and what was asked for (requested). Appending
    # to a file of the user's own outside the chat starts from a copy of it.
    def write_file_to_shared_folder(filepath:, content:, mode: "write", workbench: nil)
      unless %w[write append].include?(mode)
        return { success: false, error: "Invalid mode. Use 'write' to overwrite or 'append' to add to existing file" }
      end

      place = CHAT_FILES.for_write(filepath, caller: workbench, app_name: file_tools_app_name(workbench))
      guard = Monadic::Utils::SharedPathGuard
      existed = !guard.file_stat(place.full).nil?
      original_size = existed ? guard.file_stat(place.full).size : 0
      copied_from = nil
      if mode == "append" && !existed && place.moved
        copied_from = copy_source_for_append(filepath, workbench)
      end

      guard.mkdir_p!(File.dirname(place.full), strict: true)
      text = content.to_s.encode("UTF-8")
      if copied_from
        guard.write_file!(place.full, copied_from[:bytes] + text, strict: true)
      else
        guard.write_file!(place.full, text, mode: mode == "append" ? "a" : "w", strict: true)
      end
      stat = guard.file_stat(place.full)
      raise Errno::ENOENT unless stat

      action = if copied_from then "copied_and_appended"
               elsif mode == "append" && existed then "appended"
               elsif existed then "overwritten"
               else "created"
               end
      result = {
        success: true,
        requested: filepath,
        saved_as: place.relative,
        filepath: place.relative,
        execution_path: place.container_path,
        placed_in_chat_folder: place.moved,
        action: action,
        metadata: { size: stat.size, bytes_added: stat.size - original_size, original_size: existed ? original_size : nil }
      }
      result[:copied_from] = copied_from[:relative] if copied_from
      result[:note] = placement_note(place, copied_from) if place.moved
      result
    rescue CHAT_FILES::Refused => e
      { success: false, error: e.message, filepath: filepath }
    rescue Monadic::Utils::SharedPathGuard::InvalidPath => e
      { success: false, error: e.message, filepath: filepath }
    rescue Errno::ENOSPC
      { success: false, error: "Not enough disk space", filepath: filepath }
    rescue Errno::EACCES
      { success: false, error: "Permission denied", filepath: filepath }
    rescue StandardError => e
      { success: false, error: "Error writing file: #{e.class.name.split('::').last}", filepath: filepath }
    end

    # List a folder: this chat's work/ when none is named, a folder of this
    # chat, or one the user made. The folders of other chats are not shown
    # (the top level lists conversations/ without what is in it).
    def list_files_in_shared_folder(directory: nil, workbench: nil)
      place = CHAT_FILES.for_list(directory, caller: workbench, app_name: file_tools_app_name(workbench))
      guard = Monadic::Utils::SharedPathGuard
      guard.mkdir_p!(place.full, strict: true) if place.source == :chat && place.relative.end_with?("/#{CHAT_FILES::WORK}")
      dir = if place.relative.empty?
              File.realpath(Monadic::Utils::Environment.data_path)
            else
              guard.directory_stat(place.full) && place.full
            end
      return { success: false, error: "Directory not found", path: place.relative } unless dir

      directories = []
      files = []
      Dir.children(dir).reject { |e| e.start_with?('.') }.sort.each do |entry|
        stat = File.lstat(File.join(dir, entry))
        if stat.symlink?
          files << { name: entry, type: "link" }
        elsif stat.directory?
          if place.relative.empty? && CHAT_FILES.conversations_name?(entry)
            directories << { name: entry, type: "directory", note: "chat folders; only this chat's own is readable" }
          else
            directories << { name: entry, type: "directory", items: Dir.children(File.join(dir, entry)).reject { |e| e.start_with?('.') }.size }
          end
        else
          files << { name: entry, type: "file", size: stat.size, modified_at: stat.mtime.iso8601, extension: File.extname(entry) }
        end
      rescue Errno::ENOENT
        next
      end
      {
        success: true,
        path: place.relative.empty? ? "/" : place.relative,
        execution_path: place.container_path,
        directories: directories,
        files: files,
        total_directories: directories.size,
        total_files: files.size,
        total_items: directories.size + files.size
      }
    rescue CHAT_FILES::Refused => e
      { success: false, error: e.message, path: directory }
    rescue Monadic::Utils::SharedPathGuard::InvalidPath, Errno::ENOTDIR
      { success: false, error: "Directory not found", path: directory }
    rescue Errno::EACCES
      { success: false, error: "Permission denied accessing directory", path: directory }
    rescue StandardError => e
      { success: false, error: "Error listing files: #{e.class.name.split('::').last}", path: directory }
    end

    private

    def file_tools_app_name(workbench)
      app = workbench&.session&.dig(:parameters, "app_name")
      app.to_s.empty? ? self.class.name : app
    end

    # The user's own file the model named, when it is outside the chat:
    # { relative:, bytes: } to start an append from, or nil.
    def copy_source_for_append(filepath, workbench)
      source = CHAT_FILES.for_read(filepath, caller: workbench, app_name: file_tools_app_name(workbench))
      return nil unless source.source == :shared

      bytes = Monadic::Utils::SharedPathGuard.read_bytes!(source.full, strict: true)
      { relative: source.relative, bytes: bytes.force_encoding("UTF-8") }
    rescue CHAT_FILES::Refused, Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
      nil
    end

    def placement_note(place, copied_from)
      base = "Files of this chat are kept in its folder: this one was saved at #{place.relative}, " \
             "not at #{place.requested}. Use #{place.relative} with the file tools and " \
             "#{place.container_path} in code."
      copied_from ? "#{base} It starts with a copy of #{copied_from[:relative]}, which was left as it was." : base
    end
  end
end
