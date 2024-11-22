module MonadicHelper
  def get_dockerfile
    command = <<~CMD
      bash -c '/usr/bin/cat /monadic/Dockerfile'
    CMD
    send_command(command: command, container: "python")
  end

  def get_pysetup
    command = <<~CMD
    bash -c '/usr/bin/cat /monadic/pysetup.sh'
    CMD
    send_command(command: command, container: "python")
  end

  def check_environment
    dockerfile = get_dockerfile
    pysetup = get_pysetup

    <<~ENV
    ### Dockerfile
    ```
    #{dockerfile}
    ```

    ### pysetup.sh
    ```
    #{pysetup}
    ```
    ENV
  end
end
