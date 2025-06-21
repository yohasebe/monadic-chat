# frozen_string_literal: true

require 'parallel'
require 'digest'

# Optimized application loader with caching and parallel loading
class OptimizedAppLoader
  CACHE_DIR = "/tmp/monadic_cache"
  CACHE_VERSION = "1.0"

  class << self
    def load_apps
      ensure_cache_dir
      
      # Get all app files
      app_files = collect_app_files
      
      # Load apps in parallel with caching
      if should_use_parallel?
        load_apps_parallel(app_files)
      else
        load_apps_sequential(app_files)
      end
    end

    private

    def ensure_cache_dir
      FileUtils.mkdir_p(CACHE_DIR) unless File.exist?(CACHE_DIR)
    end

    def collect_app_files
      files = []
      
      # Built-in apps
      files += Dir.glob(File.join(File.dirname(__FILE__), "../apps/**/*.rb"))
      files += Dir.glob(File.join(File.dirname(__FILE__), "../apps/**/*.mdsl"))
      
      # User apps
      user_app_dir = IN_CONTAINER ? "/monadic/data/apps" : "#{Dir.home}/monadic/data/apps"
      if File.exist?(user_app_dir)
        files += Dir.glob(File.join(user_app_dir, "**/*.rb"))
        files += Dir.glob(File.join(user_app_dir, "**/*.mdsl"))
      end
      
      # Plugin apps
      plugin_dir = IN_CONTAINER ? "/monadic/data/plugins" : "#{Dir.home}/monadic/data/plugins"
      if File.exist?(plugin_dir)
        files += Dir.glob(File.join(plugin_dir, "**/apps/**/*.rb"))
        files += Dir.glob(File.join(plugin_dir, "**/apps/**/*.mdsl"))
      end
      
      files.uniq
    end

    def should_use_parallel?
      # Use parallel loading only if we have many files and multiple cores
      return false if ENV['MONADIC_NO_PARALLEL'] == 'true'
      
      cpu_count = Parallel.processor_count
      cpu_count > 1
    end

    def load_apps_parallel(app_files)
      # Group files by directory to reduce contention
      grouped_files = app_files.group_by { |f| File.dirname(f) }
      
      # Load each group in parallel
      Parallel.each(grouped_files.values, in_threads: 4) do |files|
        files.each { |file| load_app_file_cached(file) }
      end
    end

    def load_apps_sequential(app_files)
      app_files.each { |file| load_app_file_cached(file) }
    end

    def load_app_file_cached(file_path)
      cache_key = generate_cache_key(file_path)
      cache_path = File.join(CACHE_DIR, cache_key)
      
      # Check if we can use cached version
      if use_cache?(file_path, cache_path)
        begin
          load_from_cache(cache_path)
          return
        rescue => e
          # Fall back to normal loading if cache fails
          puts "Cache load failed for #{file_path}: #{e.message}" if ENV['DEBUG']
        end
      end
      
      # Normal loading
      load_app_file(file_path)
      
      # Update cache for next time
      update_cache(file_path, cache_path)
    end

    def generate_cache_key(file_path)
      # Create a unique cache key based on file path and content
      content_hash = Digest::SHA256.hexdigest(File.read(file_path))
      path_hash = Digest::SHA256.hexdigest(file_path)
      "#{CACHE_VERSION}_#{path_hash}_#{content_hash}.cache"
    end

    def use_cache?(file_path, cache_path)
      return false unless File.exist?(cache_path)
      
      # Cache is valid if it's newer than the source file
      File.mtime(cache_path) > File.mtime(file_path)
    end

    def load_from_cache(cache_path)
      Marshal.load(File.binread(cache_path))
    end

    def update_cache(file_path, cache_path)
      # For now, we don't cache Ruby/MDSL execution results
      # This is a placeholder for future optimization
    end

    def load_app_file(file_path)
      case File.extname(file_path)
      when '.rb'
        require file_path
      when '.mdsl'
        # MDSL loading logic
        content = File.read(file_path)
        # Process MDSL content...
      end
    end
  end
end