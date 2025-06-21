# frozen_string_literal: false

# Optimized version of monadic.rb with performance improvements

# Load performance profiler first
require_relative "monadic/utils/startup_profiler"

StartupProfiler.measure("Core Dependencies") do
  # Essential dependencies loaded immediately
  require "active_support"
  require "active_support/core_ext/hash/indifferent_access"
  require "json"
  require "dotenv"
  require "securerandom"
  require "uri"
  require "cgi"
end

# Set up lazy loading for heavy dependencies
require_relative "monadic/utils/lazy_loader"
LazyLoader.setup_lazy_loaders

StartupProfiler.measure("Constants and Helpers") do
  # Essential constants
  $MODELS = ActiveSupport::HashWithIndifferentAccess.new
  IN_CONTAINER = File.file?("/.dockerenv")
  
  # Core modules
  require_relative "monadic/version"
  require_relative "monadic/utils/setup"
  require_relative "monadic/utils/debug_helper"
  require_relative "monadic/utils/string_utils"
end

StartupProfiler.measure("Configuration") do
  # Load environment configuration
  envpath = File.expand_path Paths::ENV_PATH
  Dotenv.load(envpath)
  
  # Initialize CONFIG with defaults
  CONFIG = {
    "DISTRIBUTED_MODE" => "off",
    "EXTRA_LOGGING" => ENV["EXTRA_LOGGING"] == "true" || false,
    "JUPYTER_PORT" => "8889",
    "OLLAMA_AVAILABLE" => ENV["OLLAMA_AVAILABLE"] == "true"
  }.merge(ENV.to_h.select { |k, _| k.start_with?("MONADIC_", "OPENAI_", "ANTHROPIC_") })
end

# Defer heavy operations
module DeferredLoading
  class << self
    def load_web_dependencies
      require "eventmachine"
      require "faye/websocket"
      require "http"
      require "http/form_data"
      require "httparty"
      require "net/http"
    end

    def load_text_processing
      require "commonmarker"
      require "pragmatic_segmenter"
      require "rouge"
      require "cld"
      require "i18n_data"
    end

    def load_parsing_dependencies
      require "nokogiri"
      require "yaml"
      require "csv"
      require "strscan"
    end

    def load_database_connection
      require_relative "monadic/utils/text_embeddings"
      EMBEDDINGS_DB = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end

    def load_helpers
      require_relative "monadic/utils/interaction_utils"
      require_relative "monadic/utils/websocket"
      helpers StringUtils
      helpers InteractionUtils
      helpers WebSocketHelper
    end

    def load_apps
      require_relative "monadic/app"
      require_relative "monadic/dsl"
      
      # Use optimized app loader if available
      if File.exist?(File.join(File.dirname(__FILE__), "monadic/utils/optimized_app_loader.rb"))
        require_relative "monadic/utils/optimized_app_loader"
        OptimizedAppLoader.load_apps
      else
        # Fallback to standard loading
        load_standard_apps
      end
    end

    def load_standard_apps
      # Standard app loading logic
      Dir.glob(File.join(File.dirname(__FILE__), "monadic/apps/**/*.{rb,mdsl}")).each do |file|
        require file if file.end_with?('.rb')
        # Handle MDSL files...
      end
    end
  end
end

# Default prompt suffix (constant, no need to defer)
DEFAULT_PROMPT_SUFFIX = <<~PROMPT
When creating a numbered list in Markdown that contains code blocks or other content within list items, please follow these formatting rules:

1. Each list item's content (including code blocks, paragraphs, or nested lists) should be indented with 4 spaces from the list marker position
2. Code blocks within list items should be indented with 4 spaces plus the standard code block syntax
3. Ensure there is a blank line before and after code blocks, tables, headings, paragraphs, lists, and other elements (including those within list items)
4. The indentation must be maintained for all content belonging to the same list item

Please format all numbered lists following these rules to ensure proper rendering.
PROMPT

# Sinatra application setup (deferred until needed)
require 'sinatra/base'

class MonadicChat < Sinatra::Base
  configure do
    # Defer loading until first request
    before do
      unless @dependencies_loaded
        StartupProfiler.measure("Deferred Dependencies") do
          DeferredLoading.load_web_dependencies
          DeferredLoading.load_text_processing
          DeferredLoading.load_parsing_dependencies
          DeferredLoading.load_helpers
        end
        @dependencies_loaded = true
      end
    end
  end

  # Routes will be defined here...
end

# Report startup performance if profiling is enabled
at_exit do
  StartupProfiler.report if ENV['PROFILE_STARTUP'] == 'true'
end