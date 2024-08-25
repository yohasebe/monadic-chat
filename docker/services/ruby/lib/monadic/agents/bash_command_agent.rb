module MonadicAgent
  def lib_installer(command: "", packager: "")
    install_command = case packager
                      when "pip"
                        "pip install #{command}"
                      when "apt"
                        "apt-get install -y #{command}"
                      else
                        "echo 'Invalid packager'"
                      end

    send_command(command: install_command,
                 container: "python",
                 success: "The library #{command} has been installed successfully.\n")
  end

  def run_bash_command(command: "")
    send_command(command: command,
                 container: "python",
                 success: "Command executed successfully.\n")
  end
end
