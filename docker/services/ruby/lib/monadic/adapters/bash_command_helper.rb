require 'shellwords'

module MonadicHelper
  def lib_installer(command: "", packager: "")
    # Safely escape the package name to prevent command injection
    escaped_package = Shellwords.escape(command)
    
    install_command = case packager
                      when "pip"
                        "pip install #{escaped_package}"
                      when "apt"
                        "apt-get install -y #{escaped_package}"
                      else
                        "echo 'Invalid packager'"
                      end

    send_command(command: install_command,
                 container: "python",
                 success: "The library has been installed successfully.\n",
                 success_with_output: "The install command has been has been executed with the following output:\n")
  end

  def run_bash_command(command: "")
    # Note: This method executes arbitrary commands and should be used with caution
    # The command is passed to send_command which handles escaping
    send_command(command: command,
                 container: "python",
                 success: "The command has been executed.\n",
                 success_with_output: "Command has been executed with the following output:\n")
  end
end
