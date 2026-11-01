module MonadicHelper

  def system_info
    command = "sysinfo.sh"
    send_command(command: command, container: "python")
  end

  def get_dockerfile
    command = "/usr/bin/cat /monadic/Dockerfile 2>/dev/null"
    send_command(command: command, container: "python")
  end

  # The user's setup scripts are not in the images (they reach the builds as
  # secrets), so only the Dockerfile is shown. What a setup script installed
  # can be listed in the container (for example with `pip list`).
  def check_environment
    dockerfile = get_dockerfile

    <<~ENV
    ### Dockerfile
    ```
    #{dockerfile}
    ```

    Packages added by the user's setup script are not listed here; run `pip list` to see every installed package.
    ENV
  end
end
