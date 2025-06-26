# frozen_string_literal: true

require "open3"
require "timeout"
require "net/http"

# Manages Docker containers for testing
class DockerContainerManager
  SERVICES_DIR = File.expand_path("../../..", __dir__)
  REQUIRED_SERVICES = {
    "pgvector" => "pgvector/compose.yml",
    "selenium" => "selenium/compose.yml",
    "python" => "python/compose.yml"
  }.freeze
  HEALTH_CHECK_TIMEOUT = 60
  
  class << self
    def ensure_containers_running
      # Check if all containers are already running and healthy
      if containers_healthy?
        puts "\n✅ All required containers are already running!\n\n"
        return
      end
      
      puts "\n⚡ Starting required containers for tests..."
      start_missing_containers
      wait_for_containers_ready
      puts "✅ All containers are ready!\n\n"
    rescue => e
      puts "❌ Failed to start containers: #{e.message}"
      raise
    end
    
    def stop_containers
      puts "\n🛑 Stopping test containers..."
      REQUIRED_SERVICES.each do |service, compose_file|
        compose_path = File.join(SERVICES_DIR, compose_file)
        system("docker compose -f #{compose_path} stop", 
               out: File::NULL, err: File::NULL)
      end
    end
    
    private
    
    def containers_healthy?
      REQUIRED_SERVICES.keys.all? do |service|
        running = container_running?(service)
        healthy = service_healthy?(service)
        puts "[DEBUG] #{service}: running=#{running}, healthy=#{healthy}" if ENV['DEBUG_CONTAINERS']
        running && healthy
      end
    end
    
    def container_running?(service)
      container_name = "monadic-chat-#{service}-container"
      output, status = Open3.capture2("docker ps --format '{{.Names}}'")
      if ENV['DEBUG_CONTAINERS']
        puts "[DEBUG] Looking for container: #{container_name}"
        puts "[DEBUG] Docker ps output: #{output.inspect}"
        puts "[DEBUG] Found: #{output.include?(container_name)}"
      end
      return false unless status.success?
      output.include?(container_name)
    end
    
    def container_exists?(service)
      container_name = "monadic-chat-#{service}-container"
      output, status = Open3.capture2("docker ps -a --format '{{.Names}}'")
      return false unless status.success?
      output.include?(container_name)
    end
    
    def service_healthy?(service)
      case service
      when "pgvector"
        postgres_healthy?
      when "selenium"
        selenium_healthy?
      when "python"
        python_healthy?
      else
        true
      end
    end
    
    def postgres_healthy?
      require "pg"
      
      # Quick check if container is in healthy state
      container_name = "monadic-chat-pgvector-container"
      output, = Open3.capture2("docker inspect --format='{{.State.Health.Status}}' #{container_name} 2>/dev/null")
      
      # If Docker reports healthy, trust it
      return true if output.strip == "healthy"
      
      # Otherwise try to connect
      conn = PG.connect(
        host: ENV["IN_CONTAINER"] ? "monadic-chat-pgvector-container" : "localhost",
        port: 5433,
        user: "postgres",
        password: "postgres",
        dbname: "postgres",
        connect_timeout: 5
      )
      conn.exec("SELECT 1")
      conn.close
      true
    rescue PG::Error => e
      # Only print detailed errors in debug mode
      if ENV['DEBUG_CONTAINERS'] && !e.message.include?("starting up")
        puts "[DEBUG] PostgreSQL health check failed: #{e.message}"
      end
      false
    end
    
    def selenium_healthy?
      uri = URI("http://localhost:4444/wd/hub/status")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue
      false
    end
    
    def python_healthy?
      uri = URI("http://localhost:5070/health")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue
      false
    end
    
    def start_missing_containers
      # Check which containers are missing or stopped
      missing_services = REQUIRED_SERVICES.keys.reject { |service| container_running?(service) }
      
      if missing_services.empty?
        puts "All containers are running, checking health..."
        return
      end
      
      # Check if containers exist but are stopped
      stopped_services = missing_services.select { |service| container_exists?(service) && !container_running?(service) }
      new_services = missing_services - stopped_services
      
      # Start stopped containers
      stopped_services.each do |service|
        container_name = "monadic-chat-#{service}-container"
        puts "Starting stopped container: #{container_name}"
        cmd = "docker start #{container_name}"
        output, status = Open3.capture2e(cmd)
        unless status.success?
          puts "Failed to start #{container_name}: #{output}"
        end
      end
      
      # Create new containers if needed
      if new_services.any?
        puts "Creating new containers: #{new_services.join(', ')}"
        compose_path = File.join(SERVICES_DIR, "compose.yml")
        
        service_names = new_services.map { |s| "#{s}_service" }
        cmd = "docker compose -f #{compose_path} up -d #{service_names.join(' ')}"
        output, status = Open3.capture2e(cmd)
        
        unless status.success?
          puts "Docker compose output: #{output}"
          # Try to start containers one by one if bulk start fails
          new_services.each do |service|
            individual_cmd = "docker compose -f #{compose_path} up -d #{service}_service"
            individual_output, individual_status = Open3.capture2e(individual_cmd)
            unless individual_status.success?
              puts "Failed to create #{service}: #{individual_output}"
            end
          end
        end
      end
    end
    
    def wait_for_containers_ready
      interrupted = false
      trap("INT") { interrupted = true }
      
      start_time = Time.now
      unhealthy_count = 0
      
      loop do
        if interrupted
          puts "\n\n❌ Container startup interrupted by user"
          exit 1
        end
        
        if Time.now - start_time > HEALTH_CHECK_TIMEOUT
          puts "\n❌ Timeout: Containers failed to become healthy within #{HEALTH_CHECK_TIMEOUT} seconds"
          raise "Container startup timeout"
        end
        
        print "\r⏳ Waiting for containers: "
        
        statuses = REQUIRED_SERVICES.keys.map do |service|
          running = container_running?(service)
          healthy = service_healthy?(service)
          
          if running && healthy
            print "✅ #{service} "
            true
          elsif running
            print "🟡 #{service} "
            false
          else
            print "⏸️  #{service} "
            false
          end
        end
        
        puts
        
        if statuses.all?
          break
        else
          unhealthy_count += 1
          # If pgvector stays unhealthy for too long, try restarting it
          if unhealthy_count > 15 && !statuses[0]  # pgvector is first
            puts "\n⚠️  pgvector is taking too long, attempting restart..."
            system("docker restart monadic-chat-pgvector-container")
            unhealthy_count = 0
          end
          sleep 2
        end
      end
    ensure
      trap("INT", "DEFAULT")
    end
  end
end