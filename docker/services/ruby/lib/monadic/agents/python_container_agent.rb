module MonadicAgent
  def get_dockerfile
    command = <<~CMD
      bash -c '/usr/bin/cat /monadic/Dockerfile'
    CMD
    send_command(command: command, container: "python")
  end
end
