# frozen_string_literal: true

require_relative '../jupyter_lab'
require_relative '../container_dependencies'

# A notebook the user opens in JupyterLab (a link in the conversation or
# the work screen's button). JupyterLab is started when it does not answer,
# and the page is given the notebook's address once it does; opening a
# chat from the history, or a tool making or running a notebook, does not
# start it. The page names a notebook of the shared folder by its path;
# nothing else it sends (a host, an address, a command) is taken. The
# answer goes to the connection that asked, with its request.
module WebSocketHelper
  JUPYTER_REQUEST_MAX = 64

  private def handle_ws_jupyter_open(connection, obj, session)
    reply = { 'type' => 'jupyter_opened', 'request' => obj['request'].to_s[0, JUPYTER_REQUEST_MAX] }
    path = Monadic::Utils::JupyterLab.notebook_path(obj['path'])
    return send_to_client(connection, reply.merge('success' => false, 'error' => 'not_a_notebook')) unless path

    unless Monadic::Utils::ContainerDependencies.container_running?(:python)
      Monadic::Utils::ContainerDependencies.start_service_async(:python, reason: 'opening a notebook in JupyterLab')
      return send_to_client(connection, reply.merge('success' => false, 'error' => 'python_starting'))
    end

    tab = Thread.current[:websocket_session_id]
    Thread.new do
      started = Monadic::Utils::JupyterLab.start
      answer = if started
                 reply.merge('success' => true, 'url' => Monadic::Utils::JupyterLab.notebook_url(path))
               else
                 reply.merge('success' => false, 'error' => 'not_started')
               end
      send_or_broadcast(answer.to_json, tab)
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Jupyter] Not opened: #{e.class}" }
      send_or_broadcast(reply.merge('success' => false, 'error' => 'not_started').to_json, tab)
    end
    nil
  end
end
