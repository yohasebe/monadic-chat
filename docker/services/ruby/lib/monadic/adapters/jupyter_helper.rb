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
                 command = "sh -c 'jupyter_controller.py add_from_json #{filename} #{tempfile}' "
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
    command = "sh -c 'jupyter_controller.py create #{filename}'"
    
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
        jupyter_port = ENV["JUPYTER_PORT"] || "8889"
        
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
                "sh -c 'run_jupyter.sh run'"
              when "stop"
                "sh -c 'run_jupyter.sh stop'"
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
    jupyter_port = ENV["JUPYTER_PORT"] || "8889"
    "http://#{jupyter_host}:#{jupyter_port}"
  end
end
