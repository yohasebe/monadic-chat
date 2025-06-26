module MonadicHelper

  JUPYTER_RUN_TIMEOUT = 600
  JUPYTER_LOG_FILE = if IN_CONTAINER
                       "/monadic/log/jupyter.log"
                     else
                       Dir.home + "/monadic/log/jupyter.log"
                     end

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

    File.open(JUPYTER_LOG_FILE, "a") do |f|
      f.puts "Time: #{Time.now}"
      f.puts "Cells: #{cells_str}"
      f.puts "-----------------------------------"
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


  def add_jupyter_cells(filename: "", cells: "", run: false, escaped: false, retrial: false)

    original_cells = cells.dup

    capture_add_cells(cells)

    # remove escape characters from the cells
    if escaped
      if cells.is_a?(Array)
        cells.each do |cell|
          if cell.is_a?(Hash)
            begin
              content = cell["content"] || cell[:content]
              content = unescape(content)
              cell["content"] = content
            rescue StandardError
              cell["content"] = content
            end
          else
            cell = unescape(cell)
          end
        end
      end
    end

    return "Error: Filename is required." if filename == ""
    return "Error: Proper cell data is required; Probably the structure is ill-formatted." if cells == ""

    begin
      cells_in_json = cells.to_json
    rescue StandardError => e
      unless retrial
        return add_jupyter_cells(filename: filename,
                                 cells: original_cells,
                                 escaped: !escaped,
                                 retrial: true)
      else
        return "Error: The cells data provided could not be converted to JSON.\n#{original_cells}"
      end
    end

    tempfile = Time.now.to_i.to_s
    write_to_file(filename: tempfile, extension: "json", text: cells_in_json)

    shared_volume = if IN_CONTAINER
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
                 send_command(command: command,
                              container: "python",
                              success: "The cells have been added to the notebook successfully.\n")
               else
                 false
               end

    if results1
      # Generate access URL
      notebook_url = get_jupyter_notebook_url(filename)
      
      if run.to_s == "true"
        results2 = run_jupyter_cells(filename: filename)
        "#{results1}\n\n#{results2}\n\nAccess the notebook at: #{notebook_url}"
      else
        "#{results1}\n\nAccess the notebook at: #{notebook_url}"
      end
    else
      "Error: The cells provided could not be added to the notebook. Please correct the cells data and try again: #{original_cells}"
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

    shared_volume = if IN_CONTAINER
                      MonadicApp::SHARED_VOL
                    else
                      MonadicApp::LOCAL_SHARED_VOL
                    end
    filepath = File.join(shared_volume, filename)

    if res
      output = get_last_cell_output(filepath)
      if output
        "The last cell output is: #{output}"
      else
        "The notebook has been executed successfully."
      end
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
        # Get base jupyter URL
        jupyter_url = get_jupyter_base_url
        result = "Access the notebook at: #{jupyter_url}/lab/tree/#{notebook_filename}"
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
  
  # Delete a cell from notebook
  def delete_jupyter_cell(filename: "", index: 0)
    return "Error: Filename is required." if filename.empty?
    
    command = "jupyter_controller.py delete '#{filename}' #{index}"
    send_command(command: command, container: "python")
  end
  
  # Update a cell in notebook
  def update_jupyter_cell(filename: "", index: 0, content: "", cell_type: "code")
    return "Error: Filename is required." if filename.empty?
    return "Error: Content is required." if content.empty?
    
    # Escape content for shell command
    escaped_content = content.gsub("'", "'\\''")
    
    command = "jupyter_controller.py update '#{filename}' #{index} '#{escaped_content}' #{cell_type}"
    send_command(command: command, container: "python")
  end
  
  # Get all cells with their execution results
  def get_jupyter_cells_with_results(filename: "")
    return "Error: Filename is required." if filename.empty?
    
    notebook_path = if IN_CONTAINER
                      "/monadic/data/#{filename}.ipynb"
                    else
                      "#{Dir.home}/monadic/data/#{filename}.ipynb"
                    end
    
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
end
