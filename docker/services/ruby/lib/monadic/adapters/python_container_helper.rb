module MonadicHelper

  def system_info
    command = "sysinfo.sh"
    send_command(command: command, container: "python")
  end

  def get_dockerfile
    command = "/usr/bin/cat /monadic/Dockerfile 2>/dev/null"
    send_command(command: command, container: "python")
  end

  def get_rbsetup
    command = "/usr/bin/cat /monadic/rbsetup.sh 2>/dev/null"
    send_command(command: command, container: "ruby")
  end

  def get_pysetup
    command = "/usr/bin/cat /monadic/pysetup.sh 2>/dev/null"
    send_command(command: command, container: "python")
  end

  def check_environment
    dockerfile = get_dockerfile
    rbsetup = get_rbsetup
    pysetup = get_pysetup

    <<~ENV
    ### Dockerfile
    ```
    #{dockerfile}
    ```

    ### rbsetup.sh
    ```
    #{rbsetup}
    ```

    ### pysetup.sh
    ```
    #{pysetup}
    ```
    ENV
  end
end
