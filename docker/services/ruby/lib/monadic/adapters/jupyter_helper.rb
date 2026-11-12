require 'shellwords'
require 'erb'
require 'securerandom'
require_relative '../utils/shared_path_guard'
require_relative '../utils/extra_logger'
require_relative '../utils/jupyter_lab'

module MonadicHelper

  JUPYTER_RUN_TIMEOUT = 600
  # How long a whole run may take: longer than one cell may.
  JUPYTER_RUN_LIMIT = JUPYTER_RUN_TIMEOUT + 60
  # Cells go to the container as one argument, which Linux limits to 128 KiB.
  INSERT_LIMIT = 100_000
  JUPYTER_LOG_FILE = if Monadic::Utils::Environment.in_container?
                       "/monadic/log/jupyter.log"
                     else
                       Dir.home + "/monadic/log/jupyter.log"
                     end

  # Japanese font configuration code for matplotlib
  JAPANESE_FONT_SETUP = <<~PYTHON
    # Configure matplotlib for Japanese text support
    import matplotlib.pyplot as plt
    import matplotlib.font_manager as fm
    import warnings
    import os

    # Suppress font warnings
    warnings.filterwarnings('ignore', message='Glyph .* missing from font')

    # Configure Japanese fonts
    try:
        # Try to use Noto Sans CJK JP if available
        font_paths = [
            '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
            '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
            '/usr/share/fonts/opentype/ipafont/ipag.ttf',
            '/usr/share/fonts/truetype/ipafont/ipag.ttf'
        ]

        font_configured = False
        for font_path in font_paths:
            if os.path.exists(font_path):
                fm.fontManager.addfont(font_path)
                font_prop = fm.FontProperties(fname=font_path)
                font_name = font_prop.get_name()
                plt.rcParams['font.sans-serif'] = [font_name] + plt.rcParams['font.sans-serif']
                font_configured = True
                print(f"Japanese font configured: {font_name}")
                break

        if not font_configured:
            # Fallback to system configuration
            plt.rcParams['font.sans-serif'] = ['Noto Sans CJK JP', 'IPAGothic', 'IPAPGothic'] + plt.rcParams['font.sans-serif']
            print("Using system Japanese font configuration")

        plt.rcParams['font.family'] = 'sans-serif'
        plt.rcParams['axes.unicode_minus'] = False

    except Exception as e:
        print(f"Warning: Could not configure Japanese fonts: {e}")
        print("Japanese text may not display correctly in plots")
  PYTHON

  def unescape(text)
    text.gsub(/\\n/) { "\n" }
      .gsub(/\\'/) { "'" }
      .gsub(/\\"/) { '"' }
      .gsub(/\\\\/) { "\\" }
  end

  def capture_add_cells(cells)
    begin
      cells_str = YAML.dump(cells)
    rescue StandardError
      cells_str = cells.to_s
    end

    begin
      begin
        Monadic::Utils::Environment.rotate_log(JUPYTER_LOG_FILE)
      rescue StandardError
      end
      File.open(JUPYTER_LOG_FILE, "a") do |f|
        f.puts "Time: #{Time.now}"
        f.puts "Cells: #{Monadic::Utils::SecretRedactor.redact(cells_str)}"
        f.puts "-----------------------------------"
      end
      Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Logged to #{JUPYTER_LOG_FILE}" }
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Failed to write log: #{e.message}" }
    end
  end
  
  # Verify that cells were actually added to the notebook
  def verify_cells_added(filename, expected_cells)
    begin
      filename = shared_relative(filename)
      return { success: false, error: "Invalid shared notebook path" } unless filename
      # Add .ipynb extension only if not already present
      filename_with_ext = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
      
      # Use the same path resolution as other Jupyter functions
      shared_volume = if Monadic::Utils::Environment.in_container?
                        MonadicApp::SHARED_VOL
                      else
                        MonadicApp::LOCAL_SHARED_VOL
                      end
      notebook_path = File.join(shared_volume, filename_with_ext)
      
      # Read as a plain file of the shared folder, never through a link.
      text = (Monadic::Utils::SharedPathGuard.read_bytes!(notebook_path) rescue nil)
      return { success: false, error: "Notebook file not found at #{notebook_path}" } unless text

      notebook = JSON.parse(text)
      actual_cell_count = notebook['cells'].length
      expected_cell_count = expected_cells.is_a?(Array) ? expected_cells.length : 0
      
      # Basic verification - just check if cells were added
      if actual_cell_count > 0
        { success: true }
      else
        { success: false, error: "No cells found in notebook after addition" }
      end
    rescue StandardError => e
      { success: false, error: "Verification error: #{e.message}" }
    end
  end
  
  # Log Jupyter-related errors for debugging
  def log_jupyter_error(operation, filename, cells, error_message)
    begin
      begin
        Monadic::Utils::Environment.rotate_log(JUPYTER_LOG_FILE)
      rescue StandardError
      end
      File.open(JUPYTER_LOG_FILE, "a") do |f|
        f.puts "ERROR Time: #{Time.now}"
        f.puts "Operation: #{operation}"
        f.puts "Filename: #{filename}"
        f.puts "Error: #{Monadic::Utils::SecretRedactor.redact(error_message)}"
        f.puts "Cells attempted: #{Monadic::Utils::SecretRedactor.redact(cells.inspect[0..500])}" # Limit length
        f.puts "==================================="
      end
    rescue StandardError
      # Silently fail if logging fails
    end
  end

  def get_last_cell_output(notebook_path)
    notebook = JSON.parse(File.read(notebook_path))

    # Select code cells that have outputs

    executed_cells = notebook['cells'].select do |cell|
      cell['cell_type'] == 'code' && !cell['outputs'].empty?
    end

    return nil if executed_cells.empty?

    last_cell = executed_cells.last
    last_output = last_cell['outputs'].last

    # Extract and format the output based on its type

    case last_output['output_type']
    when 'execute_result'
      last_output['data']['text/plain']
    when 'stream'
      last_output['text']
    when 'display_data'
      last_output['data']['text/plain']
    when 'error'
      # Join traceback messages and remove ANSI escape sequences

      last_output['traceback']
        .join("\n")
        .gsub(/\e\[[0-9;]*m/, '')
    else
      nil
    end
  end


  # Normalize cell format to ensure correct structure
  def normalize_cell_format(cells)
    return cells unless cells.is_a?(Array)
    
    cells.map do |cell|
      next cell unless cell.is_a?(Hash)
      
      # Extract cell_type and source regardless of order or key type
      cell_type = cell["cell_type"] || cell[:cell_type] || cell["type"] || cell[:type] || "code"
      source = cell["source"] || cell[:source] || cell["content"] || cell[:content] || ""
      
      # Ensure source is a string (not an array)
      source = source.is_a?(Array) ? source.join("\n") : source.to_s
      
      # Return normalized structure with correct order
      {
        "cell_type" => cell_type.to_s,
        "source" => source
      }
    end
  end

  def add_jupyter_cells(filename: "", cells: "", run: true, escaped: false, retrial: false)
    # A path in the shared folder (a chat's notebook is in its folder).
    filename = shared_relative(filename)
    return "Error: Invalid shared notebook path" unless filename

    original_cells = cells.dup

    # Debug: Log before processing
    Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] add_jupyter_cells called with filename: #{filename}, cells count: #{cells.is_a?(Array) ? cells.length : 'not array'}" }

    # Handle case where filename doesn't have timestamp but the actual file does
    # If the exact filename doesn't exist, try to find a matching file with timestamp
    if filename && !filename.empty? && !filename.end_with?(".ipynb")
      shared_volume = if Monadic::Utils::Environment.in_container?
                        MonadicApp::SHARED_VOL
                      else
                        MonadicApp::LOCAL_SHARED_VOL
                      end
      
      # Handle both with and without .ipynb extension
      filename_with_ext = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
      exact_path = File.join(shared_volume, filename_with_ext)

      # If exact file doesn't exist, look for files with timestamp pattern
      unless File.exist?(exact_path)
        # Handle case where Grok uses fake timestamp like "20241001_120000"
        # Extract base name without any timestamp (and without extension)
        base_without_ext = filename_with_ext.sub(/\.ipynb$/, '')
        base_name = base_without_ext.gsub(/_\d{8}_\d{6}$/, '')  # Remove fake timestamp if present
        
        # Look for files with the same base name but different (real) timestamps
        pattern = File.join(shared_volume, "#{base_name}_*.ipynb")
        matching_files = Dir.glob(pattern).sort_by { |f| File.mtime(f) }.reverse
        
        if matching_files.any?
          # Use the most recently created matching file
          most_recent = matching_files.first
          original_filename = filename  # Store original for logging
          filename = File.basename(most_recent, ".ipynb")
          Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Found matching notebook with real timestamp: #{filename} (was looking for #{original_filename})" }

          # Log for debugging
          Monadic::Utils::ExtraLogger.log { "Corrected fake timestamp in add_jupyter_cells:\n  Original filename: #{original_filename}\n  Base name: #{base_name}\n  Found file: #{filename}" }
        end
      end
    end

    # remove escape characters from the cells
    if escaped
      if cells.is_a?(Array)
        cells.each do |cell|
          if cell.is_a?(Hash)
            begin
              content = cell["content"] || cell[:content] || cell["source"] || cell[:source]
              content = unescape(content) if content
              if cell["content"] || cell[:content]
                cell["content"] = content
              elsif cell["source"] || cell[:source]
                cell["source"] = content
              end
            rescue StandardError
              # Keep original content on error
            end
          else
            cell = unescape(cell)
          end
        end
      end
    end

    if filename == ""
      require_relative '../utils/error_handler'
      return ErrorHandler.format_validation_error(
        field: "Filename",
        requirement: "Please provide a notebook filename"
      )
    end
    
    # More detailed error reporting for cells parameter
    if cells.nil?
      require_relative '../utils/error_handler'
      return ErrorHandler.format_validation_error(
        field: "Cells",
        requirement: "Expected an array of cell objects",
        value: nil
      )
    elsif cells == ""
      require_relative '../utils/error_handler'
      return ErrorHandler.format_validation_error(
        field: "Cells",
        requirement: "Expected an array of cell objects with 'cell_type' and 'source' properties",
        value: ""
      )
    elsif !cells.is_a?(Array)
      require_relative '../utils/error_handler'
      return ErrorHandler.format_validation_error(
        field: "Cells",
        requirement: "Expected an array of cell objects, but received #{cells.class}",
        value: cells.class.to_s
      )
    elsif cells.empty?
      require_relative '../utils/error_handler'
      return ErrorHandler.format_validation_error(
        field: "Cells array",
        requirement: "Please provide at least one cell with 'cell_type' and 'source' properties",
        value: "empty array"
      )
    end
    
    # Normalize cell format before processing
    cells = normalize_cell_format(cells) if cells.is_a?(Array)
    
    # Log cells AFTER normalization
    capture_add_cells(cells)
    
    # Debug: Log after normalization
    Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] After normalization, cells: #{cells.inspect[0..500]}" }

    begin
      cells_in_json = cells.to_json
      Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] JSON conversion successful, length: #{cells_in_json.length}" }
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] JSON conversion failed: #{e.message}" }
      unless retrial
        return add_jupyter_cells(filename: filename,
                                 cells: original_cells,
                                 escaped: !escaped,
                                 retrial: true)
      else
        return "Error: The cells data provided could not be converted to JSON.\n#{original_cells}"
      end
    end

    # Check if we need to add Japanese font setup
    cells_array = JSON.parse(cells_in_json) rescue []
    if cells_array.is_a?(Array) && needs_japanese_font_setup?(cells_array)
      # Check if font setup is already present
      has_font_setup = cells_array.any? do |cell|
        cell["metadata"] && cell["metadata"]["tags"] && cell["metadata"]["tags"].include?("font-setup")
      end

      unless has_font_setup
        # Find the first matplotlib import or create at beginning
        import_index = cells_array.index do |cell|
          source = cell["source"] || ""
          source = source.join("\n") if source.is_a?(Array)
          source.match?(/import\s+matplotlib|from\s+matplotlib/)
        end

        # Insert font setup right after imports or at the beginning
        insert_position = import_index ? import_index + 1 : 0
        cells_array.insert(insert_position, create_japanese_font_setup_cell)
        cells_in_json = JSON.pretty_generate(cells_array)

        Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Added Japanese font setup cell at position #{insert_position}" }
      end
    end

    # The cells reach the Python container through a file in the shared
    # folder; its name is the call's own (two chats can add cells in the same
    # second), and it is removed once the container has read it.
    tempfile = "jupyter_cells_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(4)}"
    Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Writing to temp file: #{tempfile}.json" }
    write_to_file(filename: tempfile, extension: "json", text: cells_in_json)

    shared_volume = if Monadic::Utils::Environment.in_container?
                      MonadicApp::SHARED_VOL
                    else
                      MonadicApp::LOCAL_SHARED_VOL
                    end
    filepath = File.join(shared_volume, tempfile + ".json")

    success = false
    max_retrial = 20
    max_retrial.times do
      sleep 1.5
      if File.exist?(filepath)
        success = true
        break
      end
    end

    results1 = if success
                 # Use Shellwords.escape for safe command construction
                 command = "jupyter_controller.py add_from_json #{Shellwords.escape(filename)} #{Shellwords.escape(tempfile)}"
                 Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Executing command: #{command}" }
                 result = send_command(command: command,
                              container: "python",
                              success: "The cells have been added to the notebook successfully.\n")
                 Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Command result: #{result}" }
                 
                 # Check if the error is about missing notebook file
                 if result && result.include?("does not exist")
                   # Provide more helpful error message
                   available_notebooks = Dir.glob(File.join(shared_volume, "*.ipynb")).map { |f| File.basename(f, ".ipynb") }
                   if available_notebooks.any?
                     similar = available_notebooks.select { |nb| nb.start_with?(filename.split("_").first) }
                     if similar.any?
                       "Error: Notebook '#{filename}' not found. Did you mean one of these? #{similar.join(', ')}. Please use the exact filename with timestamp returned by create_jupyter_notebook."
                     else
                       "Error: Notebook '#{filename}' not found. Available notebooks: #{available_notebooks.join(', ')}. Please use the exact filename with timestamp."
                     end
                   else
                     "Error: Notebook '#{filename}' not found and no notebooks exist. Please create a notebook first using create_jupyter_notebook."
                   end
                 else
                   result
                 end
               else
                 Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] JSON file not created in time" }
                 false
               end
    begin
      Monadic::Utils::SharedPathGuard.delete_file!(filepath)
    rescue SystemCallError, Monadic::Utils::SharedPathGuard::InvalidPath
      nil
    end

    if results1
      # Generate access URL
      notebook_url = get_jupyter_notebook_url(filename)
      
      # Verify cells were actually added by checking the notebook
      verification_result = verify_cells_added(filename, cells)
      
      if verification_result[:success]
        if run.to_s == "true"
          results2 = run_jupyter_cells(filename: filename)
          "#{results1}\n\n#{results2}\n\nAccess the notebook at: #{notebook_url}"
        else
          "#{results1}\n\nAccess the notebook at: #{notebook_url}"
        end
      else
        # Log the verification failure
        log_jupyter_error("Cell verification failed", filename, cells, verification_result[:error])
        "Warning: Cells may not have been added correctly. #{verification_result[:error]}\n\nAccess the notebook at: #{notebook_url}"
      end
    else
      error_msg = "Error: The cells provided could not be added to the notebook."
      log_jupyter_error("Failed to add cells", filename, original_cells, error_msg)
      "#{error_msg} Please correct the cells data and try again."
    end
  end

  # Runs every cell of the notebook in a new kernel (each run starts one;
  # nothing is kept between runs). Says whether the run itself failed (it
  # could not start, ran out of time or was stopped) apart from cells that
  # raised errors, which do not stop the run.
  def run_jupyter_cells(filename:)
    name = filename.to_s.end_with?('.ipynb') ? filename.to_s : "#{filename}.ipynb"
    notebook_path = Monadic::Utils::SharedPathGuard.resolve_in_shared(name, extensions: %w[.ipynb])
    return "Error: Invalid shared notebook path" unless notebook_path

    command_path = Monadic::Utils::SharedPathGuard.command_path(notebook_path, container: "python")
    return "Error: Invalid shared notebook path" unless command_path

    command = "jupyter nbconvert --to notebook --execute #{Shellwords.escape(command_path)} --ExecutePreprocessor.timeout=#{JUPYTER_RUN_TIMEOUT} --allow-errors --inplace"
    ran, detail = notebook_command(command, timeout: JUPYTER_RUN_LIMIT)
    return "Error: The notebook could not be run to the end. #{detail}".strip unless ran

    "The cells have been executed.#{notebook_error_report(name)}"
  end

  # What cells raised when the notebook last ran ("" when none did).
  def notebook_error_report(filename)
    cells = get_jupyter_cells_with_results(filename: filename)
    return "" unless cells.is_a?(Array)

    failed = cells.select { |cell| cell[:has_error] }
    return "\n✓ All #{cells.length} cells executed successfully without errors." if failed.empty?

    lines = failed.map do |cell|
      "\n• Cell #{cell[:index]} (#{cell[:error_type]}): #{cell[:error_message]}\n  Code: #{cell[:source].to_s[0..100]}..."
    end
    "\n\n⚠️  ERRORS DETECTED IN NOTEBOOK:\n#{lines.join}\n\nTotal cells: #{cells.length}, Cells with errors: #{failed.length}\n" \
      "Use get_jupyter_cells_with_results(filename: \"#{filename}\") for full error details."
  end

  # Runs a command in the Python container: [true, what it printed] when it
  # ended well, [false, what it said went wrong] otherwise (it failed, ran
  # out of time or was stopped).
  def notebook_command(command, timeout: nil)
    send_command(command: command, container: "python", timeout: timeout) do |stdout, stderr, status|
      if status.success?
        [true, stdout.to_s.strip]
      else
        [false, Monadic::Utils::ErrorFormatter.scrub_identifiers(stderr.to_s.strip)]
      end
    end
  end

  # Helper method to generate access URL for an existing notebook
  def get_jupyter_notebook_url(filename)
    # Ensure filename has .ipynb extension
    filename = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
    
    "#{get_jupyter_base_url}/lab/tree/#{filename.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')}"
  end

  # A path relative to the shared folder (its container path taken as
  # one), or nil for one outside it.
  def shared_relative(filename)
    text = filename.to_s.delete_prefix("#{Monadic::Utils::SharedPathGuard::CONTAINER_ROOT}/")
    return nil if text.empty? || text.start_with?('/') || text.split('/').include?('..')

    text
  end

  # Combined function for Gemini to create notebook and add cells in one call
  def create_and_populate_jupyter_notebook(filename:, cells: [], run: true)
    Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] create_and_populate_jupyter_notebook called\n  Filename: #{filename}\n  Cells count: #{cells.is_a?(Array) ? cells.length : 'not array'}\n  Run cells: #{run}" }

    # First create the notebook
    result = create_jupyter_notebook(filename: filename)
    
    if result && result.include?("successfully")
      # Extract the actual filename with timestamp
      actual_filename = nil
      if result =~ /Notebook '([^']+\.ipynb)'/
        actual_filename = $1.sub('.ipynb', '')
      elsif result =~ /([^\/\s]+_\d{8}_\d{6})\.ipynb/
        actual_filename = $1
      end
      
      if actual_filename && cells && cells.is_a?(Array) && !cells.empty?
        Monadic::Utils::ExtraLogger.log { "[DEBUG Jupyter] Adding cells to notebook: #{actual_filename}" }
        # Now add the cells
        cells_result = add_jupyter_cells(
          filename: actual_filename,
          cells: cells,
          run: run
        )
        
        # Combine the results
        "#{result}\n\n#{cells_result}"
      else
        result
      end
    else
      result
    end
  end
  
  # Helper method to create Japanese font setup cell
  def create_japanese_font_setup_cell
    {
      "cell_type" => "code",
      "source" => JAPANESE_FONT_SETUP,
      "metadata" => {
        "tags" => ["font-setup"]
      }
    }
  end

  # Check if notebook needs Japanese font setup
  def needs_japanese_font_setup?(cells)
    # Check if any cell contains Japanese text or matplotlib usage
    cells.any? do |cell|
      source = cell["source"] || cell[:source] || ""
      source = source.join("\n") if source.is_a?(Array)

      # Check for Japanese characters or matplotlib imports
      source.match?(/[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]/) ||  # Japanese characters
      source.match?(/import\s+matplotlib/) ||                          # matplotlib import
      source.match?(/from\s+matplotlib/) ||                           # matplotlib from import
      source.match?(/plt\./)                                          # plt usage
    end
  end

  def create_jupyter_notebook(filename:)
    begin
      # Sanitize filename to prevent directory traversal and command injection
      filename = File.basename(filename.to_s)
      # filename extension is not required and removed if provided
      filename = filename.split(".")[0]
    rescue StandardError
      filename = ""
    end
    # Use Shellwords.escape for safe command construction
    command = "jupyter_controller.py create #{Shellwords.escape(filename)}"
    
    # Get result from command
    result = send_command(command: command, container: "python")
    
    # If successful, construct a proper URL with the notebook filename
    if result && !result.start_with?("Error:")
      # Extract filename from Python response
      # Try all possible formats: "Notebook created: filename.ipynb" or "Notebook created at /path/filename.ipynb"
      notebook_filename = nil
      
      if result.include?("Notebook created: ")
        # Format: "Notebook created: filename.ipynb"
        notebook_filename = result.split("Notebook created: ").last.strip
      elsif result.include?("Notebook created at ")
        # Format: "Notebook created at /path/filename.ipynb"
        full_path = result.split("Notebook created at ").last.strip
        notebook_filename = File.basename(full_path)
      end
      
      if notebook_filename
        # Return in the format expected by Grok's process_functions
        # This format allows extraction of the actual filename with timestamp
        result = "Notebook #{notebook_filename} created successfully. Access it at: #{get_jupyter_notebook_url(notebook_filename)}"
      else
        # For backward compatibility, handle old format responses
        jupyter_host = get_jupyter_host
        jupyter_port = CONFIG["JUPYTER_PORT"] || ENV["JUPYTER_PORT"] || "8889"
        
        # Replace any 127.0.0.1:8889 or localhost:8889 with the proper host:port
        result = result.gsub(/127\.0\.0\.1:8889/, "#{jupyter_host}:#{jupyter_port}")
        result = result.gsub(/localhost:8889/, "#{jupyter_host}:#{jupyter_port}")
        
        # Ensure we have http:// prefix for proper linking
        unless result.include?("http://") || result.include?("https://")
          result = result.gsub(/#{jupyter_host}:#{jupyter_port}/, "http://#{jupyter_host}:#{jupyter_port}")
        end
      end
    end
    
    result
  end

  def run_jupyter(command: "")
    action = case command
             when "start", "run" then "run"
             when "stop" then "stop"
             else
               return "Error: Invalid command."
             end

    jupyter_url = get_jupyter_base_url
    shell_cmd = "run_jupyter.sh #{action}"

    output = send_command(command: shell_cmd, container: "python")

    # Always append the access URL for "run" so the model knows where
    # JupyterLab is — send_command's `success` parameter is only used
    # when stdout is empty, but run_jupyter.sh always produces output.
    if action == "run" && !output.include?("Error")
      "#{output}\nSuccess: Access JupyterLab at #{jupyter_url}/lab"
    else
      output
    end
  end
  
  private
  
  # JupyterLab is published on this machine only
  def get_jupyter_host
    Monadic::Utils::JupyterLab::HOST
  end

  # Get complete Jupyter base URL
  def get_jupyter_base_url
    Monadic::Utils::JupyterLab.base_url
  end
  
  public

  # List all Jupyter notebooks in the data directory
  def list_jupyter_notebooks
    data_path = Monadic::Utils::Environment.data_path
    notebooks = Dir.glob(File.join(data_path, "*.ipynb")).map do |path|
      {
        filename: File.basename(path, ".ipynb"),
        path: path,
        modified: File.mtime(path),
        size: File.size(path)
      }
    end
    
    if notebooks.empty?
      "No Jupyter notebooks found in the data directory."
    else
      notebooks.sort_by { |nb| nb[:modified] }.reverse.map do |nb|
        "- #{nb[:filename]} (modified: #{nb[:modified].strftime('%Y-%m-%d %H:%M:%S')})"
      end.join("\n")
    end
  end
  
  # Delete a cell from notebook
  def delete_jupyter_cell(filename: "", index: 0)
    return "Error: Filename is required." if filename.empty?

    command = "jupyter_controller.py delete #{Shellwords.shellescape(filename)} #{index}"
    send_command(command: command, container: "python")
  end
  
  # Update a cell in notebook
  def update_jupyter_cell(filename: "", index: 0, content: "", cell_type: "code")
    return "Error: Filename is required." if filename.empty?
    return "Error: Content is required." if content.empty?

    command = "jupyter_controller.py update #{Shellwords.shellescape(filename)} #{index} #{Shellwords.shellescape(content)} #{cell_type}"
    send_command(command: command, container: "python")
  end
  
  # Get all cells with their execution results
  def get_jupyter_cells_with_results(filename: "")
    return "Error: Filename is required." if filename.empty?

    # Handle both with and without .ipynb extension
    filename_with_ext = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
    notebook_path = File.join(Monadic::Utils::Environment.data_path, filename_with_ext)
    
    # Read as a plain file of the shared folder, never through a link.
    text = (Monadic::Utils::SharedPathGuard.read_bytes!(notebook_path) rescue nil)
    return "Error: Notebook not found." unless text

    begin
      notebook = JSON.parse(text)
      cells_with_results = []
      
      notebook['cells'].each_with_index do |cell, index|
        cell_info = {
          index: index,
          type: cell['cell_type'],
          source: cell['source'].is_a?(Array) ? cell['source'].join : cell['source']
        }
        
        if cell['cell_type'] == 'code' && cell['outputs'] && !cell['outputs'].empty?
          outputs = cell['outputs']
          cell_info[:has_error] = outputs.any? { |o| o['output_type'] == 'error' }
          
          if cell_info[:has_error]
            error_output = outputs.find { |o| o['output_type'] == 'error' }
            cell_info[:error_type] = error_output['ename']
            cell_info[:error_message] = error_output['evalue']
            cell_info[:traceback] = error_output['traceback'].join("\n").gsub(/\e\[[0-9;]*m/, '')
          else
            # Collect non-error outputs
            cell_info[:outputs] = outputs.map do |output|
              case output['output_type']
              when 'execute_result'
                if output['data']
                  if output['data']['image/png']
                    "[Image output]"
                  else
                    output['data']['text/plain']
                  end
                end
              when 'stream'
                output['text']
              when 'display_data'
                if output['data'] && output['data']['image/png']
                  "[Image output]"
                elsif output['data']
                  output['data']['text/plain']
                end
              end
            end.compact
          end
        end
        
        cells_with_results << cell_info
      end
      
      cells_with_results
    rescue StandardError => e
      "Error reading notebook: #{e.message}"
    end
  end
  
  # Execute cells and fix errors with retry limit
  def execute_and_fix_jupyter_cells(filename: "", max_retries: 3)
    return "Error: Filename is required." if filename.empty?
    
    retry_count = 0
    fixed_cells = []
    
    while retry_count < max_retries
      # Get current state of all cells
      cells_info = get_jupyter_cells_with_results(filename: filename)
      return cells_info if cells_info.is_a?(String) && cells_info.start_with?("Error:")
      
      # Find cells with errors
      error_cells = cells_info.select { |cell| cell[:has_error] }
      
      break if error_cells.empty? # All cells executed successfully
      
      retry_count += 1
      
      # Process each error cell
      error_cells.each do |error_cell|
        fixed_cells << {
          index: error_cell[:index],
          original_code: error_cell[:source],
          error_type: error_cell[:error_type],
          error_message: error_cell[:error_message],
          retry_count: retry_count
        }
        
        # Return error info for AI to fix
        return {
          status: "error_found",
          cell_index: error_cell[:index],
          cell_type: error_cell[:type],
          source: error_cell[:source],
          error_type: error_cell[:error_type],
          error_message: error_cell[:error_message],
          traceback: error_cell[:traceback],
          retry_count: retry_count,
          max_retries: max_retries
        }
      end
    end
    
    if retry_count >= max_retries
      {
        status: "max_retries_reached",
        message: "Maximum retry attempts reached. Some cells still have errors.",
        fixed_cells: fixed_cells
      }
    else
      {
        status: "success",
        message: "All cells executed successfully.",
        retry_count: retry_count
      }
    end
  end
  
  # Clears the outputs the notebook keeps. There is no kernel to restart:
  # every run starts a new one.
  def clear_jupyter_outputs(filename:)
    return "Error: Filename is required." if filename.to_s.empty?

    name = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
    full_path = Monadic::Utils::SharedPathGuard.resolve_in_shared(name, extensions: %w[.ipynb])
    return "Error: Invalid shared notebook path" unless full_path

    command_path = Monadic::Utils::SharedPathGuard.command_path(full_path, container: "python")
    return "Error: Invalid shared notebook path" unless command_path

    cleared, detail = notebook_command("jupyter nbconvert --clear-output --inplace #{Shellwords.escape(command_path)}")
    return "Error: Could not clear the outputs of #{name}. #{detail}".strip unless cleared

    "Cleared the outputs of #{name}."
  end

  # Moves a cell so that it ends at to_index (both 0-based, counted in the
  # notebook as it is). The cell keeps its outputs; nothing is run.
  def move_jupyter_cell(filename:, from_index:, to_index:)
    name = notebook_name(filename)
    return "Error: Invalid shared notebook path" unless name

    from = cell_position(from_index)
    to = cell_position(to_index)
    return "Error: Cell positions must be whole numbers from 0." unless from && to

    moved, detail = notebook_command("jupyter_controller.py move #{Shellwords.escape(name)} #{from} #{to}")
    moved ? "#{detail}." : "Error: The cell was not moved. #{detail}".strip
  end

  # Inserts cells before the cell at index (0-based; the number of cells
  # adds them at the end). With run, the whole notebook runs afterwards in
  # a new kernel, every cell of it, not only the new ones.
  def insert_jupyter_cells(filename:, index:, cells:, run: false)
    name = notebook_name(filename)
    return "Error: Invalid shared notebook path" unless name

    at = cell_position(index)
    return "Error: The position must be a whole number from 0." unless at
    return "Error: Cells are required." unless cells.is_a?(Array) && !cells.empty?

    cells_json = normalize_cell_format(cells).to_json
    return "Error: The cells are too large to insert in one call; insert them in parts." if cells_json.bytesize > INSERT_LIMIT

    inserted, detail = notebook_command("jupyter_controller.py insert #{Shellwords.escape(name)} #{at} #{Shellwords.escape(cells_json)}")
    return "Error: The cells were not inserted. #{detail}".strip unless inserted
    return "#{detail}." unless run.to_s == "true"

    "#{detail}.\n\n#{run_jupyter_cells(filename: name)}"
  end

  # A cell position given as a whole number from 0 (or its digits); nil
  # for anything else.
  def cell_position(value)
    return value if value.is_a?(Integer) && value >= 0
    return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)

    nil
  end

  # The notebook's name in the shared folder (with .ipynb) when it names a
  # notebook file there; nil otherwise.
  def notebook_name(filename)
    text = filename.to_s
    return nil if text.empty?

    name = text.end_with?(".ipynb") ? text : "#{text}.ipynb"
    Monadic::Utils::SharedPathGuard.resolve_in_shared(name, extensions: %w[.ipynb]) ? name : nil
  end
end
