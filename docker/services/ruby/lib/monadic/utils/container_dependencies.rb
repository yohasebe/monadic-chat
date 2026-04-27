# frozen_string_literal: true

require 'shellwords'

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
        pgvector: "pgvector_service",
        privacy: "privacy_service"
      }.freeze

      # Docker container names for each logical service
      CONTAINER_NAMES = {
        python: "monadic-chat-python-container",
        selenium: "monadic-chat-selenium-container",
        pgvector: "monadic-chat-pgvector-container",
        privacy: "monadic-chat-privacy-container"
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

        # Privacy: required when an app declares privacy.enabled in MDSL.
        # The privacy container itself is only built when the user opts in
        # via PRIVACY_FILTER=true; ensure-service privacy returns
        # PRIVACY_DISABLED in that case so the caller can show a setup dialog.
        if get.call(:privacy_enabled)
          services << :privacy
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

      # Fire-and-forget background trigger to ensure containers for a given
      # app name. Looks up APPS[app_name], schedules a background thread to
      # run ensure_services_for_app, and swallows errors after logging them.
      #
      # Used by callers that want to kick off startup without waiting (WebSocket
      # UPDATE_PARAMS, LOAD, and legacy HTTP redirect). Centralising the
      # Thread.new + rescue + log pattern here keeps those call sites in sync
      # and avoids per-site drift in error handling.
      #
      # @param app_name [String, nil] app_name key into APPS
      # @param reason [String] short tag for log messages
      # @return [Boolean] true if a thread was scheduled, false otherwise
      def ensure_services_async(app_name, reason: "trigger")
        return false if app_name.nil? || app_name.to_s.strip.empty?
        return false unless defined?(APPS) && APPS[app_name]

        target_settings = APPS[app_name].settings
        Thread.new do
          ensure_services_for_app(target_settings)
        rescue StandardError => e
          if defined?(Monadic::Utils::ExtraLogger)
            Monadic::Utils::ExtraLogger.log { "[ContainerDeps] #{reason}: #{e.message}" }
          end
        end
        true
      end

      # Check if a container is currently running.
      def container_running?(service)
        container_name = CONTAINER_NAMES[service]
        return false unless container_name
        output = `docker ps --format '{{.Names}}' --filter "name=#{Shellwords.escape(container_name)}" 2>/dev/null`.strip
        output.include?(container_name)
      end

      # Start a service via monadic.sh (development) or docker compose (production).
      # Returns true if the service was started or is already running.
      def start_service(service)
        service_name = service.to_s
        compose_name = COMPOSE_SERVICES[service]
        return false unless compose_name

        # Try monadic.sh first (available on host in dev mode)
        monadic_sh = find_monadic_sh
        if monadic_sh
          output = `bash #{Shellwords.escape(monadic_sh)} ensure-service #{service_name} 2>/dev/null`.strip
          return true if %w[STARTED ALREADY_RUNNING].include?(output)
        end

        # Fallback: direct docker compose (inside container with Docker socket)
        profile = service_name # profile name matches service name
        output = `docker compose -p monadic-chat --profile #{profile} up -d #{compose_name} 2>/dev/null`.strip
        $?.success?
      end

      # Locate monadic.sh in dev or packaged app environments.
      #
      # This file lives at `docker/services/ruby/lib/monadic/utils/` (5 levels
      # deep under the `docker/` folder that also contains `monadic.sh`).
      # The canonical candidate goes 5 levels up (utils → monadic → lib → ruby
      # → services → docker) then appends `monadic.sh`. Extra candidates are
      # kept for packaged Electron environments where the Ruby files may be
      # laid out slightly differently.
      def find_monadic_sh
        base = File.dirname(__FILE__)
        candidates = [
          File.expand_path("../../../../../monadic.sh", base), # dev layout: docker/monadic.sh
          File.expand_path("../../../../monadic.sh", base),    # flattened layout (no services/)
          File.expand_path("../../../../../docker/monadic.sh", base),
          File.expand_path("../../../../docker/monadic.sh", base)
        ]
        candidates.find { |path| File.exist?(path) }
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
