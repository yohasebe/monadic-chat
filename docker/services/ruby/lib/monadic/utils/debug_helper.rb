# frozen_string_literal: true

# Unified debug control system for Monadic Chat
module DebugHelper
  # Debug levels
  DEBUG_LEVELS = {
    none: 0,      # No debug output
    error: 1,     # Only errors
    warning: 2,   # Errors and warnings
    info: 3,      # General information
    debug: 4,     # Detailed debug information
    verbose: 5    # Everything including raw data
  }.freeze

  # Debug categories
  DEBUG_CATEGORIES = {
    all: "All debug messages",
    app: "General application debugging",
    embeddings: "Text embeddings operations",
    mdsl: "MDSL tool completion",
    tts: "Text-to-Speech operations",
    drawio: "DrawIO grapher operations",
    ai_user: "AI user agent",
    web_search: "Web search operations",
    api: "API requests and responses"
  }.freeze

  class << self
    # Get the current debug level from environment or config
    def debug_level
      # Check CONFIG first (from ~/monadic/config/env), then ENV (system environment)
      level = nil
      level ||= CONFIG['MONADIC_DEBUG_LEVEL'] if defined?(CONFIG) && CONFIG
      level ||= ENV['MONADIC_DEBUG_LEVEL']
      level ||= CONFIG['DEBUG_LEVEL'] if defined?(CONFIG) && CONFIG
      level ||= ENV['DEBUG_LEVEL']
      level ||= 'none'
      
      DEBUG_LEVELS[level.to_sym] || DEBUG_LEVELS[:none]
    end

    # Get enabled debug categories
    def debug_categories
      # Check CONFIG first (from ~/monadic/config/env), then ENV (system environment)
      categories = nil
      categories ||= CONFIG['MONADIC_DEBUG'] if defined?(CONFIG) && CONFIG
      categories ||= ENV['MONADIC_DEBUG']
      categories ||= CONFIG['DEBUG_CATEGORIES'] if defined?(CONFIG) && CONFIG
      categories ||= ENV['DEBUG_CATEGORIES']
      categories ||= ''
      
      return [:all] if categories.to_s.downcase == 'all' || categories.to_s == '1' || categories.to_s == 'true'
      
      categories.to_s.split(',').map(&:strip).map(&:to_sym).select { |cat| DEBUG_CATEGORIES.key?(cat) }
    end

    # Check if debugging is enabled for a specific category and level
    def debug_enabled?(category: :app, level: :debug)
      return false if debug_level == DEBUG_LEVELS[:none]
      
      categories = debug_categories
      return false if categories.empty?
      
      category_enabled = categories.include?(:all) || categories.include?(category)
      level_enabled = debug_level >= (DEBUG_LEVELS[level] || DEBUG_LEVELS[:debug])
      
      category_enabled && level_enabled
    end

    # Output debug message if enabled
    def debug(message, category: :app, level: :debug)
      return unless debug_enabled?(category: category, level: level)
      
      prefix = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{category.to_s.upcase}] [#{level.to_s.upcase}]"
      puts "#{prefix} #{message}"
    end

    # Legacy support methods
    def app_debug?
      debug_enabled?(category: :app)
    end

    def embeddings_debug?
      debug_enabled?(category: :embeddings)
    end

    def mdsl_debug?
      debug_enabled?(category: :mdsl)
    end

    def tts_debug?
      debug_enabled?(category: :tts)
    end

    def drawio_debug?
      debug_enabled?(category: :drawio)
    end

    def extra_logging?
      # Check both CONFIG (from Electron settings) and new debug system
      config_enabled = CONFIG && CONFIG['EXTRA_LOGGING'] == true
      env_enabled = debug_enabled?(category: :api, level: :info)
      
      config_enabled || env_enabled
    end

    def ai_user_debug?
      debug_enabled?(category: :ai_user)
    end

    # Migration helper to show deprecation warnings
    def check_legacy_debug_vars
      legacy_vars = {
        'APP_DEBUG' => 'app',
        'EMBEDDINGS_DEBUG' => 'embeddings',
        'MDSL_AUTO_COMPLETE' => 'mdsl',
        'DEBUG_TTS' => 'tts',
        'DRAWIO_DEBUG' => 'drawio'
      }

      legacy_found = []
      legacy_vars.each do |old_var, category|
        if ENV[old_var]
          legacy_found << "#{old_var} -> Use MONADIC_DEBUG=#{category} instead"
        end
      end

      if CONFIG && CONFIG['EXTRA_LOGGING']
        legacy_found << "CONFIG['EXTRA_LOGGING'] -> Can be controlled via Electron settings or MONADIC_DEBUG=api"
      end

      if CONFIG && CONFIG['DEBUG_AI_USER']
        legacy_found << "CONFIG['DEBUG_AI_USER'] -> Use MONADIC_DEBUG=ai_user instead"
      end

      unless legacy_found.empty?
        puts "\n⚠️  Legacy debug variables detected:"
        legacy_found.each { |msg| puts "   - #{msg}" }
        puts "\n📝 Example: export MONADIC_DEBUG=app,embeddings MONADIC_DEBUG_LEVEL=debug\n\n"
      end
    end
  end
end

# Check for legacy debug variables on load
DebugHelper.check_legacy_debug_vars if ENV['CHECK_DEBUG_MIGRATION']