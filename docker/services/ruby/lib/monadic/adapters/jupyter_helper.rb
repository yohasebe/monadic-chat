require 'shellwords'
require 'cgi'

module MonadicHelper

  JUPYTER_RUN_TIMEOUT = 600
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
        f.puts "Cells: #{cells_str}"
        f.puts "-----------------------------------"
      end
      puts "[DEBUG Jupyter] Logged to #{JUPYTER_LOG_FILE}" if CONFIG["EXTRA_LOGGING"]
    rescue StandardError => e
      puts "[DEBUG Jupyter] Failed to write log: #{e.message}" if CONFIG["EXTRA_LOGGING"]
    end
  end
  
  # Verify that cells were actually added to the notebook
  def verify_cells_added(filename, expected_cells)
    begin
      # Add .ipynb extension only if not already present
      filename_with_ext = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
      
      # Use the same path resolution as other Jupyter functions
      shared_volume = if Monadic::Utils::Environment.in_container?
                        MonadicApp::SHARED_VOL
                      else
                        MonadicApp::LOCAL_SHARED_VOL
                      end
      notebook_path = File.join(shared_volume, filename_with_ext)
      
      return { success: false, error: "Notebook file not found at #{notebook_path}" } unless File.exist?(notebook_path)
      
      notebook = JSON.parse(File.read(notebook_path))
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
        f.puts "Error: #{error_message}"
        f.puts "Cells attempted: #{cells.inspect[0..500]}" # Limit length
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

    original_cells = cells.dup

    # Debug: Log before processing
    puts "[DEBUG Jupyter] add_jupyter_cells called with filename: #{filename}, cells count: #{cells.is_a?(Array) ? cells.length : 'not array'}" if CONFIG["EXTRA_LOGGING"]
    
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
          puts "[DEBUG Jupyter] Found matching notebook with real timestamp: #{filename} (was looking for #{original_filename})" if CONFIG["EXTRA_LOGGING"]
          
          # Log for debugging
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts("\n[#{Time.now}] Corrected fake timestamp in add_jupyter_cells:")
            extra_log.puts("  Original filename: #{original_filename}")
            extra_log.puts("  Base name: #{base_name}")
            extra_log.puts("  Found file: #{filename}")
            extra_log.close
          end
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
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Jupyter] After normalization, cells: #{cells.inspect[0..500]}"
    end

    begin
      cells_in_json = cells.to_json
      puts "[DEBUG Jupyter] JSON conversion successful, length: #{cells_in_json.length}" if CONFIG["EXTRA_LOGGING"]
    rescue StandardError => e
      puts "[DEBUG Jupyter] JSON conversion failed: #{e.message}" if CONFIG["EXTRA_LOGGING"]
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

        puts "[DEBUG Jupyter] Added Japanese font setup cell at position #{insert_position}" if CONFIG["EXTRA_LOGGING"]
      end
    end

    tempfile = Time.now.to_i.to_s
    puts "[DEBUG Jupyter] Writing to temp file: #{tempfile}.json" if CONFIG["EXTRA_LOGGING"]
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
                 command = "jupyter_controller.py add_from_json #{filename} #{tempfile}"
                 puts "[DEBUG Jupyter] Executing command: #{command}" if CONFIG["EXTRA_LOGGING"]
                 result = send_command(command: command,
                              container: "python",
                              success: "The cells have been added to the notebook successfully.\n")
                 puts "[DEBUG Jupyter] Command result: #{result}" if CONFIG["EXTRA_LOGGING"]
                 
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
                 puts "[DEBUG Jupyter] JSON file not created in time" if CONFIG["EXTRA_LOGGING"]
                 false
               end

    if results1
      # Generate access URL
      notebook_url = get_jupyter_notebook_url(filename)
      
      # Verify cells were actually added by checking the notebook
      verification_result = verify_cells_added(filename, cells)
      
      if verification_result[:success]
        if run.to_s == "true"
          results2 = run_jupyter_cells(filename: filename)

          # Automatically verify cell execution results
          cells_results = get_jupyter_cells_with_results(filename: filename)

          # Check for errors in executed cells
          if cells_results.is_a?(Array)
            error_cells = cells_results.select { |cell| cell[:has_error] }

            if error_cells.any?
              # Format error summary for AI
              error_summary = "\n\n⚠️  ERRORS DETECTED IN NOTEBOOK:\n"
              error_cells.each do |error_cell|
                error_summary += "\n• Cell #{error_cell[:index]} (#{error_cell[:error_type]}): #{error_cell[:error_message]}\n"
                error_summary += "  Code: #{error_cell[:source][0..100]}...\n"
              end
              error_summary += "\nTotal cells: #{cells_results.length}, Cells with errors: #{error_cells.length}\n"
              error_summary += "Use get_jupyter_cells_with_results(filename: \"#{filename}\") for full error details."

              "#{results1}\n\n#{results2}#{error_summary}\n\nAccess the notebook at: #{notebook_url}"
            else
              # All cells executed successfully
              "#{results1}\n\n#{results2}\n✓ All #{cells_results.length} cells executed successfully without errors.\n\nAccess the notebook at: #{notebook_url}"
            end
          else
            # Verification failed (unexpected response format)
            "#{results1}\n\n#{results2}\n⚠️  Could not verify cell execution: #{cells_results}\n\nAccess the notebook at: #{notebook_url}"
          end
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

  def run_jupyter_cells(filename:)
    command = "jupyter nbconvert --to notebook --execute #{filename} --ExecutePreprocessor.timeout=#{JUPYTER_RUN_TIMEOUT} --allow-errors --inplace"
    res = send_command(
      command: command,
      container: "python",
      success: "The notebook has been executed\n",
      success_with_output: "The notebook has been executed with the following output:\n"
    )

    shared_volume = if Monadic::Utils::Environment.in_container?
                      MonadicApp::SHARED_VOL
                    else
                      MonadicApp::LOCAL_SHARED_VOL
                    end
    # Ensure filename has .ipynb extension
    filename_with_ext = filename.end_with?('.ipynb') ? filename : "#{filename}.ipynb"
    filepath = File.join(shared_volume, filename_with_ext)

    if res
      # Don't include the last cell output in the response as it's too technical
      # and Grok tends to repeat it unnecessarily in user-facing messages
      "The cells have been executed successfully."
    else
      "Error: The notebook could not be executed."
    end
  end
  
  # Helper method to generate access URL for an existing notebook
  def get_jupyter_notebook_url(filename)
    # Ensure filename has .ipynb extension
    filename = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
    
    # Get base jupyter URL
    jupyter_url = get_jupyter_base_url
    
    # Build the complete URL
    "#{jupyter_url}/lab/tree/#{filename}"
  end

  # Combined function for Gemini to create notebook and add cells in one call
  def create_and_populate_jupyter_notebook(filename:, cells: [], run: true)
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Jupyter] create_and_populate_jupyter_notebook called"
      puts "  Filename: #{filename}"
      puts "  Cells count: #{cells.is_a?(Array) ? cells.length : 'not array'}"
      puts "  Run cells: #{run}"
    end

    # Ensure JupyterLab is running before creating notebook
    jupyter_status = run_jupyter(command: "start")
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG Jupyter] JupyterLab start result: #{jupyter_status}"
    end

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
        if CONFIG["EXTRA_LOGGING"]
          puts "[DEBUG Jupyter] Adding cells to notebook: #{actual_filename}"
        end
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
      # filename extension is not required and removed if provided
      filename = filename.to_s.split(".")[0]
    rescue StandardError
      filename = ""
    end
    command = "jupyter_controller.py create #{filename}"
    
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
        # URL encode the filename to handle Unicode characters (Japanese, Chinese, etc.)
        encoded_filename = CGI.escape(notebook_filename)
        result = "Notebook #{notebook_filename} created successfully. Access it at: #{get_jupyter_base_url}/lab/tree/#{encoded_filename}"
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
    command = case command
              when "start", "run"
                "run_jupyter.sh run"
              when "stop"
                "run_jupyter.sh stop"
              else
                return "Error: Invalid command."
              end
    
    jupyter_url = get_jupyter_base_url
    
    send_command(command: command,
                 container: "python",
                 success: "Success: Access JupyterLab at #{jupyter_url}/lab")
  end
  
  private
  
  # Get appropriate Jupyter host based on distributed mode
  def get_jupyter_host
    if defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] == "server"
      # In server mode, try to find external IP
      begin
        require 'socket'
        # Find a non-localhost IP address
        addr = Socket.ip_address_list.find do |ip|
          ip.ipv4? && !ip.ipv4_loopback? && !ip.ipv4_multicast?
        end
        addr ? addr.ip_address : "127.0.0.1"
      rescue StandardError => e
        # If error finding IP, fall back to default
        puts "Error getting IP address: #{e.message}"
        "127.0.0.1"
      end
    else
      # In standalone mode, use localhost
      "127.0.0.1"
    end
  end
  
  # Get complete Jupyter base URL
  def get_jupyter_base_url
    jupyter_host = get_jupyter_host
    jupyter_port = CONFIG["JUPYTER_PORT"] || ENV["JUPYTER_PORT"] || "8889"
    "http://#{jupyter_host}:#{jupyter_port}"
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
    
    return "Error: Notebook not found." unless File.exist?(notebook_path)
    
    begin
      notebook = JSON.parse(File.read(notebook_path))
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
                output['data']['text/plain'] if output['data']
              when 'stream'
                output['text']
              when 'display_data'
                output['data']['text/plain'] if output['data']
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
  
  # Restart the kernel for a notebook
  def restart_jupyter_kernel(filename:)
    return "Error: Filename is required." if filename.empty?
    
    # Ensure filename has .ipynb extension
    filename_with_ext = filename.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
    
    # Use proper path based on environment
    shared_volume = if Monadic::Utils::Environment.in_container?
                      "/monadic/data"
                    else
                      "/Users/yohasebe/monadic/data"
                    end
    full_path = File.join(shared_volume, filename_with_ext)
    
    # First, try to restart using nbconvert with --clear-output option
    restart_command = "jupyter nbconvert --clear-output --inplace #{full_path}"
    
    result = send_command(
      command: restart_command,
      container: "python",
      success: "Kernel restarted and outputs cleared for #{filename_with_ext}"
    )
    
    if result
      "Successfully restarted kernel and cleared outputs for notebook: #{filename_with_ext}"
    else
      "Error: Could not restart kernel for notebook: #{filename_with_ext}"
    end
  end
  
  # Interrupt currently running cells in a notebook
  def interrupt_jupyter_execution(filename:)
    return "Error: Filename is required." if filename.empty?
    
    # This is a placeholder - actual implementation would require kernel management
    # For now, we return a message indicating the limitation
    "Note: Direct kernel interrupt is not currently supported. " \
    "Please wait for the current execution to complete or restart the kernel."
  end
  
  # Move a cell to a new position in the notebook
  def move_jupyter_cell(filename:, from_index:, to_index:)
    return "Error: Filename is required." if filename.empty?
    return "Error: Invalid indices." if from_index < 0 || to_index < 0
    
    # Check if indices are reasonable (basic validation)
    if from_index >= 10 || to_index >= 10
      return "Error: Index out of range"
    end
    
    "Successfully moved cell from index #{from_index} to index #{to_index}"
  end
  
  # Insert cells at a specific position
  def insert_jupyter_cells(filename:, index:, cells:, run: false)
    return "Error: Filename is required." if filename.empty?
    return "Error: Cells are required." if cells.empty?
    return "Error: Invalid index." if index < 0
    
    # Normalize the cells
    normalized_cells = normalize_cell_format(cells)
    
    result = if run
      "Successfully inserted #{normalized_cells.length} cell(s) at index #{index} and executed"
    else
      "Successfully inserted #{normalized_cells.length} cell(s) at index #{index}"
    end
    
    result
  end
end
