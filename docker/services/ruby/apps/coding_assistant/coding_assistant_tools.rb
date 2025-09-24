# Coding Assistant application tools
# Provides file operations and GPT-5-Codex agent integration

require_relative '../../lib/monadic/agents/gpt5_codex_agent'

module CodingAssistantTools
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

  # Read a file from the shared folder
  def read_file_from_shared_folder(filepath:)
    begin
      data_dir = Monadic::Utils::Environment.data_path

      full_path = if filepath.start_with?('/')
                    filepath
                  else
                    File.join(data_dir, filepath)
                  end

      unless validate_file_path(full_path)
        return { error: "File path is outside the shared folder or invalid" }
      end

      unless File.exist?(full_path)
        return { error: "File '#{filepath}' not found" }
      end

      unless File.file?(full_path)
        return { error: "'#{filepath}' is a directory, not a file" }
      end

      content = File.read(full_path)

      {
        filepath: filepath,
        size: File.size(full_path),
        modified: File.mtime(full_path).iso8601,
        content: content,
        lines: content.lines.count
      }

    rescue StandardError => e
      { error: "Error reading file: #{e.message}" }
    end
  end

  # Write a file to the shared folder
  def write_file_to_shared_folder(filepath:, content:, mode: "write")
    begin
      unless ["write", "append"].include?(mode)
        return { error: "Invalid mode. Use 'write' or 'append'" }
      end

      data_dir = Monadic::Utils::Environment.data_path

      full_path = if filepath.start_with?('/')
                    filepath
                  else
                    File.join(data_dir, filepath)
                  end

      unless validate_file_path(full_path)
        return { error: "File path is outside the shared folder or invalid" }
      end

      # Ensure directory exists
      dir = File.dirname(full_path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)

      file_existed = File.exist?(full_path)
      original_size = file_existed ? File.size(full_path) : 0

      file_mode = mode == "append" ? 'a' : 'w'

      File.open(full_path, file_mode) do |f|
        f.write(content)
      end

      if File.exist?(full_path)
        file_size = File.size(full_path)
        action = if mode == "append" && file_existed
                   "appended"
                 elsif file_existed
                   "overwritten"
                 else
                   "created"
                 end

        {
          success: true,
          action: action,
          filepath: full_path,
          size: file_size,
          bytes_added: mode == "append" ? file_size - original_size : file_size
        }
      else
        { error: "File could not be verified after writing" }
      end

    rescue StandardError => e
      { error: "Error writing file: #{e.message}" }
    end
  end

  # List files in the shared folder
  def list_files_in_shared_folder(directory: nil)
    begin
      data_dir = Monadic::Utils::Environment.data_path

      if directory.nil? || directory.empty?
        target_dir = data_dir
        relative_path = "/"
      else
        directory = directory.sub(/^\//, '')
        target_dir = File.join(data_dir, directory)
        relative_path = "/#{directory}"

        unless validate_file_path(target_dir)
          return { error: "Directory path is outside the shared folder" }
        end
      end

      unless File.exist?(target_dir)
        return { error: "Directory '#{directory}' not found" }
      end

      unless File.directory?(target_dir)
        return { error: "'#{directory}' is not a directory" }
      end

      entries = Dir.entries(target_dir).reject { |e| e.start_with?('.') }

      files = []
      directories = []

      entries.sort.each do |entry|
        full_entry_path = File.join(target_dir, entry)

        if File.directory?(full_entry_path)
          item_count = Dir.entries(full_entry_path).reject { |e| e.start_with?('.') }.size
          directories << {
            name: entry,
            type: "directory",
            items: item_count
          }
        else
          files << {
            name: entry,
            type: "file",
            size: File.size(full_entry_path),
            modified: File.mtime(full_entry_path).iso8601
          }
        end
      end

      {
        path: relative_path,
        directories: directories,
        files: files,
        total_directories: directories.size,
        total_files: files.size
      }

    rescue StandardError => e
      { error: "Error listing files: #{e.message}" }
    end
  end

  # Call GPT-5-Codex agent for coding tasks
  def gpt5_codex_agent(task:, context: nil, files: nil)
    # Build prompt using the shared helper
    prompt = build_codex_prompt(
      task: task,
      context: context,
      files: files
    )

    # Call the shared GPT-5-Codex implementation
    call_gpt5_codex(prompt: prompt, app_name: "CodingAssistant")
  end
end

# Class definition for Coding Assistant with tools
class CodingAssistantOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include CodingAssistantTools
end