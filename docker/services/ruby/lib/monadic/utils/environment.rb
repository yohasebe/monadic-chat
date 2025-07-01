# frozen_string_literal: true

module Monadic
  module Utils
    # Unified environment configuration module that consolidates
    # all environment-specific logic (paths, database connections, etc.)
    module Environment
      module_function

      # Core environment detection
      def in_container?
        # Check ENV first for test flexibility, then fall back to constant
        if ENV.key?('IN_CONTAINER')
          ENV['IN_CONTAINER'] == 'true'
        elsif defined?(::IN_CONTAINER)
          ::IN_CONTAINER
        else
          File.file?("/.dockerenv")
        end
      end

      # Path resolution methods
      def resolve_path(container_path, local_path = nil)
        if in_container?
          container_path
        else
          local_path || container_path.sub('/monadic', File.join(Dir.home, 'monadic'))
        end
      end

      # Standard paths
      def config_path
        resolve_path('/monadic/config')
      end

      def env_path
        File.join(config_path, 'env')
      end

      def data_path
        resolve_path('/monadic/data')
      end

      def scripts_path
        File.join(data_path, 'scripts')
      end

      def apps_path
        File.join(data_path, 'apps')
      end

      def helpers_path
        File.join(data_path, 'helpers')
      end

      def plugins_path
        File.join(data_path, 'plugins')
      end

      # Alias for plugins_path (for backward compatibility)
      def user_plugins_path
        plugins_path
      end

      def log_path
        resolve_path('/monadic/log')
      end

      def command_log_file
        File.join(log_path, 'command.log')
      end

      def extra_log_file
        File.join(log_path, 'extra.log')
      end

      def jupyter_log_file
        File.join(log_path, 'jupyter.log')
      end

      # Shared volume paths (alias for data_path)
      def shared_volume
        data_path
      end

      # System script directories
      def system_script_dir
        resolve_path('/monadic/scripts', File.expand_path('../../../scripts', __dir__))
      end

      # Database connection methods
      def postgres_params(database: 'postgres')
        {
          host: postgres_host,
          port: postgres_port,
          user: 'postgres',
          password: 'postgres',
          dbname: database
        }
      end

      def postgres_host
        in_container? ? 'pgvector_service' : 'localhost'
      end

      def postgres_port
        in_container? ? 5432 : 5433
      end

      # Convenience method for backwards compatibility
      def self.included(base)
        base.extend(self)
      end
    end
  end
end