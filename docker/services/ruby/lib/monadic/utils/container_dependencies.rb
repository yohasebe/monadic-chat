# frozen_string_literal: true

# Determines which Docker containers an app requires based on its MDSL settings.
# Used for on-demand container startup: only start containers that the selected
# app actually needs, rather than starting all containers at boot.

module Monadic
  module Utils
    module ContainerDependencies
      # Tool groups that indicate Python container dependency
      PYTHON_TOOL_GROUPS = %i[
        python_execution
        parallel_python_execution
        jupyter_operations
      ].freeze

      # Tool groups that indicate Selenium container dependency
      SELENIUM_TOOL_GROUPS = %i[
        web_automation
      ].freeze

      # Compose service names for each logical service
      COMPOSE_SERVICES = {
        python: "python_service",
        selenium: "selenium_service",
        pgvector: "pgvector_service"
      }.freeze

      # Docker container names for each logical service
      CONTAINER_NAMES = {
        python: "monadic-chat-python-container",
        selenium: "monadic-chat-selenium-container",
        pgvector: "monadic-chat-pgvector-container"
      }.freeze

      module_function

      # Determine which extra services an app requires.
      # Returns a Set of symbols: :python, :selenium, :pgvector
      def required_services(settings)
        services = Set.new

        # Normalize key access (support both symbol and string keys)
        get = ->(key) { settings[key.to_sym].nil? ? settings[key.to_s] : settings[key.to_sym] }

        # Check imported tool groups
        tool_groups = get.call(:imported_tool_groups) || []
        group_names = tool_groups.map { |g| (g[:name] || g["name"]).to_sym }

        # Python: needed for code execution, Jupyter, data analysis
        if group_names.any? { |name| PYTHON_TOOL_GROUPS.include?(name) }
          services << :python
        end

        # Python: also needed if jupyter flag is set
        if get.call(:jupyter)
          services << :python
        end

        # Selenium: needed for web automation (always implies Python too)
        if group_names.any? { |name| SELENIUM_TOOL_GROUPS.include?(name) }
          services << :selenium
          services << :python # Selenium operations run through Python
        end

        # PGVector: needed for local PDF vector storage
        if get.call(:pdf_vector_storage)
          services << :pgvector
        end

        services
      end

      # Ensure all required services for an app are running.
      # Returns an array of service symbols that were newly started.
      def ensure_services_for_app(settings)
        needed = required_services(settings)
        return [] if needed.empty?

        started = []
        needed.each do |service|
          next if container_running?(service)
          if start_service(service)
            started << service
          end
        end
        started
      end

      # Check if a container is currently running.
      def container_running?(service)
        container_name = CONTAINER_NAMES[service]
        return false unless container_name
        output = `docker ps --format '{{.Names}}' --filter "name=#{container_name}" 2>/dev/null`.strip
        output.include?(container_name)
      end

      # Start a service via monadic.sh ensure-service command.
      # Returns true if the service was started or is already running.
      def start_service(service)
        service_name = service.to_s
        monadic_sh = File.expand_path("../../../../monadic.sh", File.dirname(__FILE__))

        # In development mode, use the source tree path
        unless File.exist?(monadic_sh)
          monadic_sh = File.expand_path("../../../../../docker/monadic.sh", File.dirname(__FILE__))
        end

        return false unless File.exist?(monadic_sh)

        output = `bash #{monadic_sh} ensure-service #{service_name} 2>/dev/null`.strip
        %w[STARTED ALREADY_RUNNING].include?(output)
      end

      # Map logical service name to Docker Compose service name
      def service_to_compose_name(service)
        COMPOSE_SERVICES[service]
      end

      # Map logical service name to Docker container name
      def service_to_container_name(service)
        CONTAINER_NAMES[service]
      end
    end
  end
end
