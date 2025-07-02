module MonadicHelper
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
                 success: "The library has been installed successfully.\n",
                 success_with_output: "The install command has been has been executed with the following output:\n")
  end

  def run_bash_command(command: "")
    send_command(command: command,
                 container: "python",
                 success: "The command has been executed.\n",
                 success_with_output: "Command has been executed with the following output:\n")
  end
end
