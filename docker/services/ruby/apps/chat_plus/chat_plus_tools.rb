# Chat Plus application tools for shared folder operations

# Module containing the shared folder operation tools
module ChatPlusTools
  include MonadicHelper
  
  # Read a file from the shared folder
  def read_file_from_shared_folder(filepath:)
    begin
      # Get the shared folder path
      data_dir = Monadic::Utils::Environment.data_path
      
      # Construct full path
      full_path = if filepath.start_with?('/')
                    filepath  # Absolute path provided
                  else
                    File.join(data_dir, filepath)  # Relative to shared folder
                  end
      
      # Validate the path is within the shared folder
      unless validate_file_path(full_path)
        return "Error: File path is outside the shared folder or invalid"
      end
      
      # Check if file exists
      unless File.exist?(full_path)
        return "Error: File '#{filepath}' not found in the shared folder"
      end
      
      # Check if it's a file (not a directory)
      unless File.file?(full_path)
        return "Error: '#{filepath}' is a directory, not a file"
      end
      
      # Read the file content
      content = File.read(full_path)
      
      # Return content with metadata
      file_info = {
        filepath: filepath,
        size: File.size(full_path),
        modified: File.mtime(full_path).iso8601,
        content: content
      }
      
      "File successfully read from shared folder:\n" +
      "Path: #{file_info[:filepath]}\n" +
      "Size: #{file_info[:size]} bytes\n" +
      "Modified: #{file_info[:modified]}\n" +
      "---\n" +
      "#{file_info[:content]}"
      
    rescue Errno::EACCES => e
      "Error: Permission denied reading file '#{filepath}'"
    rescue Errno::EISDIR => e
      "Error: '#{filepath}' is a directory, not a file"
    rescue StandardError => e
      "Error reading file: #{e.message}"
    end
  end
  
  # Write a file to the shared folder
  def write_file_to_shared_folder(filename:, extension:, content:, mode: "write")
    begin
      # Validate filename doesn't contain path separators
      if filename.include?('/') || filename.include?('\\')
        return "Error: Filename cannot contain directory paths. Use only the filename."
      end
      
      # Validate mode parameter
      unless ["write", "append"].include?(mode)
        return "Error: Invalid mode. Use 'write' to overwrite or 'append' to add to existing file."
      end
      
      # Sanitize filename and extension
      # Allow Unicode letters (including Japanese), numbers, underscore, and hyphen
      # Remove only dangerous characters for filesystem
      safe_filename = filename.gsub(/[\/\\\:\*\?\"\<\>\|]/, '_')
      safe_extension = extension.gsub(/[^a-zA-Z0-9]/, '')
      
      # Get the shared folder path
      data_dir = Monadic::Utils::Environment.data_path
      
      # Construct full path
      full_filename = "#{safe_filename}.#{safe_extension}"
      full_path = File.join(data_dir, full_filename)
      
      # Check if file exists (for user feedback)
      file_existed = File.exist?(full_path)
      original_size = file_existed ? File.size(full_path) : 0
      
      # Determine file mode
      file_mode = mode == "append" ? 'a' : 'w'
      
      # Write the file
      File.open(full_path, file_mode) do |f|
        f.write(content)
      end
      
      # Verify the file was written
      if File.exist?(full_path)
        file_size = File.size(full_path)
        action = if mode == "append" && file_existed
                   "appended to"
                 elsif file_existed
                   "overwritten"
                 else
                   "created"
                 end
        
        result = "File successfully #{action} in shared folder:\n" +
                 "Filename: #{full_filename}\n" +
                 "Path: #{full_path}\n"
        
        if mode == "append" && file_existed
          result += "Original size: #{original_size} bytes\n" +
                   "New size: #{file_size} bytes\n" +
                   "Bytes added: #{file_size - original_size} bytes"
        else
          result += "Size: #{file_size} bytes"
        end
        
        result
      else
        "Error: File could not be verified after writing"
      end
      
    rescue Errno::ENOSPC => e
      "Error: Not enough disk space to save file"
    rescue Errno::EACCES => e
      "Error: Permission denied writing to shared folder"
    rescue StandardError => e
      "Error writing file: #{e.message}"
    end
  end
  
  # List files in the shared folder
  def list_files_in_shared_folder(directory: nil)
    begin
      # Get the shared folder path
      data_dir = Monadic::Utils::Environment.data_path
      
      # Determine the directory to list
      if directory.nil? || directory.empty?
        target_dir = data_dir
        relative_path = "/"
      else
        # Remove leading slash if present
        directory = directory.sub(/^\//, '')
        target_dir = File.join(data_dir, directory)
        relative_path = "/#{directory}"
        
        # Validate the path is within the shared folder
        unless validate_file_path(target_dir)
          return "Error: Directory path is outside the shared folder or invalid"
        end
      end
      
      # Check if directory exists
      unless File.exist?(target_dir)
        return "Error: Directory '#{directory}' not found in the shared folder"
      end
      
      # Check if it's actually a directory
      unless File.directory?(target_dir)
        return "Error: '#{directory}' is not a directory"
      end
      
      # Get list of files and directories
      entries = Dir.entries(target_dir).reject { |e| e.start_with?('.') }
      
      if entries.empty?
        return "The directory '#{relative_path}' is empty"
      end
      
      # Build detailed listing
      file_list = []
      dir_list = []
      
      entries.sort.each do |entry|
        full_entry_path = File.join(target_dir, entry)
        
        if File.directory?(full_entry_path)
          dir_count = Dir.entries(full_entry_path).reject { |e| e.start_with?('.') }.size
          dir_list << "📁 #{entry}/ (#{dir_count} items)"
        else
          size = File.size(full_entry_path)
          mtime = File.mtime(full_entry_path).strftime("%Y-%m-%d %H:%M")
          
          # Format size nicely
          size_str = if size < 1024
                       "#{size} B"
                     elsif size < 1024 * 1024
                       "#{(size / 1024.0).round(1)} KB"
                     else
                       "#{(size / (1024.0 * 1024)).round(1)} MB"
                     end
          
          file_list << "📄 #{entry} (#{size_str}, #{mtime})"
        end
      end
      
      # Build response
      response = "Contents of shared folder '#{relative_path}':\n\n"
      
      unless dir_list.empty?
        response += "Directories:\n"
        dir_list.each { |d| response += "  #{d}\n" }
        response += "\n"
      end
      
      unless file_list.empty?
        response += "Files:\n"
        file_list.each { |f| response += "  #{f}\n" }
      end
      
      response += "\nTotal: #{dir_list.size} directories, #{file_list.size} files"
      
      response
      
    rescue Errno::EACCES => e
      "Error: Permission denied accessing the directory"
    rescue StandardError => e
      "Error listing files: #{e.message}"
    end
  end
end

# Class definitions for Chat Plus apps
# These must come AFTER the module definition

# Chat Plus apps with file operations
class ChatPlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include ChatPlusTools
end

class ChatPlusClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include ChatPlusTools
end

class ChatPlusGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include ChatPlusTools
end

class ChatPlusGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include ChatPlusTools
end

class ChatPlusMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include ChatPlusTools
end

class ChatPlusDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include ChatPlusTools
end

class ChatPlusCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include ChatPlusTools
end

class ChatPlusPerplexity < MonadicApp
  include PerplexityHelper if defined?(PerplexityHelper)
  include ChatPlusTools
end

class ChatPlusOllama < MonadicApp
  include OllamaHelper if defined?(OllamaHelper)
  include ChatPlusTools
end