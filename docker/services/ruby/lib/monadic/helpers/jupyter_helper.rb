module MonadicHelper

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

  def add_jupyter_cells(filename: "", cells: "", escaped: false, retrial: false)
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
      results2 = run_jupyter_cells(filename: filename)
      results1 + "\n\n" + results2
    else
      "Error: The cells provided could not be added to the notebook. Please correct the cells data and try again: #{original_cells}"
    end
  end

  def run_jupyter_cells(filename:)
    command = "jupyter nbconvert --to notebook --execute #{filename} --ExecutePreprocessor.timeout=60 --allow-errors --inplace"
    send_command(command: command,
                 container: "python",
                 success: "The notebook has been executed\n",
                 success_with_output: "The notebook has been executed with the following output:\n")
  end

  def create_jupyter_notebook(filename:)
    begin
      # filename extension is not required and removed if provided
      filename = filename.to_s.split(".")[0]
    rescue StandardError
      filename = ""
    end
    command = "sh -c 'jupyter_controller.py create #{filename}'"
    send_command(command: command, container: "python")
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
    send_command(command: command,
                 container: "python",
                 success: "Success: Access Jupter Lab at 127.0.0.1:8889/lab\n")
  end
end
