# frozen_string_literal: true

module Monadic
  module Utils
    # The server listens on this machine only and runs standalone whatever
    # the env file says. AuthMiddleware asks for the access token only when
    # DISTRIBUTED_MODE is "server"; a value left in the env file would lock
    # the desktop app out, so it is set to "off" after the file is read.
    module ServerMode
      module_function

      # Returns true when a server setting was turned off
      def normalize!(config)
        was_server = config["DISTRIBUTED_MODE"].to_s == "server"
        config["DISTRIBUTED_MODE"] = "off"
        was_server
      end
    end
  end
end
