# frozen_string_literal: false

# Optimize load path by removing duplicates
$LOAD_PATH.uniq!

require_relative "monadic/utils/ssl_configuration"
require_relative "monadic/utils/workflow_viewer_helpers"
require_relative "monadic/utils/container_dependencies"
require_relative "monadic/utils/server_mode"
require_relative "monadic/workspace"
require_relative "monadic/mcp/server"

# Optional startup profiling
if ENV['PROFILE_STARTUP'] == 'true'
  require_relative "monadic/utils/startup_profiler"
  at_exit { StartupProfiler.report }
end


require "active_support"
require "active_support/core_ext/hash/indifferent_access"
require "base64"
require "cld"
require "digest"
require "dotenv"
require "http"
require "http/form_data"
require "i18n_data"
require "json"
require "commonmarker"
require "net/http"
require "nokogiri"
require "open3"
require "securerandom"
require "strscan"
require "tempfile"
require "uri"
require "cgi"
require "yaml"
require "csv"

# Make $MODELS a HashWithIndifferentAccess so it can be accessed with both strings and symbols
$MODELS = ActiveSupport::HashWithIndifferentAccess.new

require_relative "monadic/version"

# Load environment utilities early
require_relative "monadic/utils/environment"
# Words a chat hides never leave for another service: every outbound HTTP
# request is checked where it is sent.
require_relative "monadic/utils/privacy/egress_guard"
Monadic::Utils::Privacy::EgressGuard.install!

# Backward compatibility - DEPRECATED
# All tests have been migrated. This can be removed after verifying no external dependencies.
IN_CONTAINER = Monadic::Utils::Environment.in_container?

require_relative "monadic/utils/setup"
require_relative "monadic/utils/secret_references"
require_relative "monadic/utils/env_file"
require_relative "monadic/utils/tokenizer"
require_relative "monadic/help"

require_relative "monadic/utils/string_utils"
helpers StringUtils

require_relative "monadic/utils/interaction_utils"
helpers InteractionUtils

require_relative "monadic/utils/websocket"
helpers WebSocketHelper

require_relative "monadic/utils/pdf_text_extractor"
require_relative "monadic/utils/debug_helper"
require_relative "monadic/utils/extra_logger"
require_relative "monadic/utils/json_repair"
require_relative "monadic/utils/error_pattern_detector"
require_relative "monadic/utils/model_spec_loader"
require_relative "monadic/utils/language_config"
require_relative "monadic/utils/selenium_helper"
require_relative "monadic/utils/tts_text_extractor"
require_relative "monadic/utils/tool_image_utils"

require_relative "monadic/app"
require_relative "monadic/dsl"

# Load all vendor helpers before processing app files
# This ensures MDSL files can successfully include them via DSL's "if defined?" check
require_relative "monadic/adapters/vendors/tavily_helper"
require_relative "monadic/adapters/vendors/openai_helper"
require_relative "monadic/adapters/vendors/claude_helper"
require_relative "monadic/adapters/vendors/gemini_helper"
require_relative "monadic/adapters/vendors/cohere_helper"
require_relative "monadic/adapters/vendors/deepseek_helper"
require_relative "monadic/adapters/vendors/mistral_helper"
require_relative "monadic/adapters/vendors/grok_helper"
require_relative "monadic/adapters/vendors/ollama_helper"

envpath = File.expand_path Paths::ENV_PATH
# Only the settings the code reads from ENV go there, and never one that
# decides where requests go or what program runs (EnvFile).
Monadic::Utils::SecretReferences.scrub_env!(loaded: Monadic::Utils::EnvFile.load!(envpath))

# Include TavilyHelper for tavily_fetch method
include TavilyHelper

# The logs are written into this folder, which a new install does not have yet.
FileUtils.mkdir_p(Monadic::Utils::Environment.log_path)

DEFAULT_PROMPT_SUFFIX = <<~PROMPT
When creating a numbered list in Markdown that contains code blocks or other content within list items, please follow these formatting rules:

1. Each list item's content (including code blocks, paragraphs, or nested lists) should be indented with 4 spaces from the list marker position
2. Code blocks within list items should be indented with 4 spaces plus the standard code block syntax
3. Ensure there is a blank line before and after code blocks, tables, headings, paragraphs, lists, and other elements (including those within list items)
4. The indentation must be maintained for all content belonging to the same list item

Example format:

1. First item

    ```python
    # This code block is indented with 4 spaces
    print("Hello")
    ```

    Continuation text for first item (also indented with 4 spaces)

2. Second item

    - Nested list (indented with 4 spaces)
    - Another nested item

Please format all numbered lists following these rules to ensure proper rendering.
PROMPT

# Initialize CONFIG with default values
CONFIG = {
  "DISTRIBUTED_MODE" => "off",  # Default to off/standalone mode
  "EXTRA_LOGGING" => ENV["EXTRA_LOGGING"] == "true" || false,  # Check ENV first, then default to false
  "DEBUG_MODE" => ENV["DEBUG_MODE"] == "true" || false,  # Check if running in debug mode
  "JUPYTER_PORT" => "8889",     # Default Jupyter port
  "WEBSOCKET_PROGRESS_ENABLED" => ENV["WEBSOCKET_PROGRESS_ENABLED"] != "false",  # Default to true, can be disabled via ENV
  "AUTO_TTS_MAX_BYTES" => 400  # Maximum bytes for auto TTS in post-completion mode (default: 400 bytes ≈ 130 Japanese chars or 400 ASCII chars)
}

unresolved_references = []
begin
  # The file's settings through EnvFile, the same parse that gave ENV its
  # values: nothing in a value is expanded or run, and a proxy, a service
  # address, a program path, a port that is not a number or a file in the
  # shared folder is not taken.
  raise Errno::ENOENT, Paths::ENV_PATH unless File.exist?(Paths::ENV_PATH)

  Monadic::Utils::EnvFile.accepted(Paths::ENV_PATH).each do |key, value|
    # A 1Password reference (op://...) stands for the value; an unresolved
    # one leaves the key unset rather than passing the reference on.
    if Monadic::Utils::SecretReferences.reference?(value)
      value = Monadic::Utils::SecretReferences.resolve(key, value)
      if value.nil?
        unresolved_references << key
        next
      end
    end
    
    # Skip empty API keys
    if key.end_with?("_API_KEY") && (value.nil? || value.empty?)
      next
    end
    
    if value.nil?
      puts "Warning: Empty value for key '#{key}'"
      next # Skip empty values instead of storing them as empty strings
    end

    CONFIG[key] = Monadic::Utils::SecretReferences.setting_value(key, value)
  end
  
  Monadic::Utils::SecretReferences.record_unresolved(unresolved_references)
  unless unresolved_references.empty?
    puts "1Password references not resolved, left unset: #{unresolved_references.join(', ')}"
  end

  # Override with environment variables if they exist
  # This allows rake server:debug to force EXTRA_LOGGING=true and DEBUG_MODE=true
  if ENV["EXTRA_LOGGING"]
    CONFIG["EXTRA_LOGGING"] = ENV["EXTRA_LOGGING"] == "true"
  end
  if ENV["DEBUG_MODE"]
    CONFIG["DEBUG_MODE"] = ENV["DEBUG_MODE"] == "true"
  end
rescue Errno::ENOENT
  puts "Environment file not found at #{Paths::ENV_PATH}"
  CONFIG["ERROR"] = "Environment file not found. Default configuration will be used."
rescue Errno::EACCES
  puts "Permission denied when trying to read environment file at #{Paths::ENV_PATH}"
  CONFIG["ERROR"] = "Permission denied when trying to read environment file. Default configuration will be used."
rescue JSON::ParserError => e
  puts "JSON parsing error in environment file: #{e.message}"
  CONFIG["ERROR"] = "Configuration file contains invalid JSON: #{e.message}"
rescue StandardError => e
  puts "Error loading environment file: #{e.message}\n#{e.backtrace.join("\n")}"
  CONFIG["ERROR"] = "Error loading configuration: #{e.message}"
end

# Runs after the env file is read, or failed to be read, so the access
# check stays off on every path
Monadic::Utils::ServerMode.normalize!(CONFIG)

# Configure SSL defaults after environment has been processed
begin
  Monadic::Utils::SSLConfiguration.configure!(CONFIG)
rescue => e
  puts "Warning: Failed to configure SSL defaults: #{e.message}"
end

# Workflow Viewer helpers: extract graph data from app settings
# Workflow Viewer helpers — delegated to Monadic::Utils::WorkflowViewerHelpers
def wv_extract_tools(s) = Monadic::Utils::WorkflowViewerHelpers.wv_extract_tools(s)
def wv_extract_shared_tool_groups(s) = Monadic::Utils::WorkflowViewerHelpers.wv_extract_shared_tool_groups(s)
def wv_extract_agents(s) = Monadic::Utils::WorkflowViewerHelpers.wv_extract_agents(s)
def wv_extract_features(s) = Monadic::Utils::WorkflowViewerHelpers.wv_extract_features(s)
def wv_generates_image?(s) = Monadic::Utils::WorkflowViewerHelpers.wv_generates_image?(s)
def wv_accepts_image_upload?(s) = Monadic::Utils::WorkflowViewerHelpers.wv_accepts_image_upload?(s)

def handle_error(message)
  session[:error] = message
  redirect "/"
end

# Load app files
def load_app_files
  apps_to_load = {}
  base_app_dir = File.join(__dir__, "..", "apps")
  user_apps_dir = Monadic::Utils::Environment.apps_path

  # Initialize global error tracking variable
  $MONADIC_LOADING_ERRORS = []

  # 1. Built-in apps (docker/services/ruby/apps/)
  Dir["#{File.join(base_app_dir, "**") + File::SEPARATOR}*.{rb,mdsl}"].sort.each do |file|
    basename = File.basename(file)
    next if basename.start_with?("_") # ignore files that start with an underscore
    next if file.include?("/test/") # ignore test directories

    # If the basename already exists as a key, create a unique key by adding a suffix
    if apps_to_load.key?(basename)
      unique_basename = "#{basename}_#{SecureRandom.hex(4)}"
      apps_to_load[unique_basename] = file
    else
      apps_to_load[basename] = file
    end
  end

  # 2. User apps (~/monadic/data/apps/)
  # (never through a link, and in development mode only when asked: see SharedPathGuard.user_code_files)
  if Dir.exist?(user_apps_dir)
    Monadic::Utils::SharedPathGuard.user_code_files(user_apps_dir, File.join("**", "*.{rb,mdsl}")).each do |file|
      basename = File.basename(file)
      next if basename.start_with?("_")
      next if file.include?("/test/")
      next if file.include?("/helpers/") # skip helper directories inside app folders
      next if file.include?("/services/") # skip service directories inside app folders

      if apps_to_load.key?(basename)
        unique_basename = "#{basename}_#{SecureRandom.hex(4)}"
        apps_to_load[unique_basename] = file
      else
        apps_to_load[basename] = file
      end
    end
  end

  # sort apps_to_load so that rb files come before mdsl files
  apps_to_load = apps_to_load.sort_by { |k, _v| k.end_with?(".rb") ? 0 : 1 }.to_h

  apps_to_load.each_value do |file|
    MonadicDSL::Loader.load(file)
  end
  
  # Report loading errors if any occurred
  if $MONADIC_LOADING_ERRORS && !$MONADIC_LOADING_ERRORS.empty?
    error_count = $MONADIC_LOADING_ERRORS.size
    puts "\n\033[31m⚠️  #{error_count} app#{error_count > 1 ? 's' : ''} failed to load:\033[0m"
    
    $MONADIC_LOADING_ERRORS.each_with_index do |error, idx|
      puts "  #{idx + 1}. \033[33m#{error[:app]}\033[0m (#{File.basename(error[:file])})"
      puts "     Error: #{error[:error]}"
    end
    puts "\n"
  end
end

# Load the TTS dictionary
def load_tts_dict(tts_dict_data = nil)
  tts_dict = {}
  
  # 1. Check for TTS_DICT.csv in the config directory first (for Docker container)
  config_dict_path = File.join(Monadic::Utils::Environment.config_path, "TTS_DICT.csv")
  
  if File.exist?(config_dict_path)
    begin
      file_data = File.read(config_dict_path)
      tts_dict = StringUtils.process_tts_dictionary(file_data)
      Monadic::Utils::ExtraLogger.log { "TTS Dictionary loaded with #{tts_dict.size} entries from config directory" }
      CONFIG["TTS_DICT"] = tts_dict
      return
    rescue => e
      Monadic::Utils::ExtraLogger.log { "Error reading TTS dictionary from config: #{e.message}" }
    end
  end
  
  # 2. For development mode with 'rake debug': If TTS_DICT_PATH exists, read directly from that path
  if ENV['TTS_DICT_PATH'] && File.exist?(ENV['TTS_DICT_PATH'])
    begin
      file_data = File.read(ENV['TTS_DICT_PATH'])
      tts_dict = StringUtils.process_tts_dictionary(file_data)
      Monadic::Utils::ExtraLogger.log { "TTS Dictionary loaded with #{tts_dict.size} entries from TTS_DICT_PATH (development mode)" }
    rescue => e
      Monadic::Utils::ExtraLogger.log { "Error reading TTS dictionary from TTS_DICT_PATH: #{e.message}" }
    end
  # 3. Legacy support: Try using TTS_DICT_DATA if it exists
  elsif tts_dict_data || CONFIG["TTS_DICT_DATA"]
    data_to_process = tts_dict_data || CONFIG["TTS_DICT_DATA"]
    tts_dict = StringUtils.process_tts_dictionary(data_to_process)
    Monadic::Utils::ExtraLogger.log { "TTS Dictionary loaded with #{tts_dict.size} entries from TTS_DICT_DATA (legacy mode)" }
  else
    Monadic::Utils::ExtraLogger.log { "No TTS Dictionary data available" }
  end
  
  CONFIG["TTS_DICT"] = tts_dict || {}
end

# Initialize apps
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")
  
  # If in debug mode, log we're processing apps
  Monadic::Utils::ExtraLogger.log { "Initializing apps in normal mode" }
  
  klass.subclasses.each do |a|
    app = a.new
    class_settings = a.instance_variable_get(:@settings)
    
    # Debug: Log reasoning_effort for OpenAI apps
    if a.name.include?("OpenAI")
      Monadic::Utils::ExtraLogger.log { "#{a.name} class settings: reasoning_effort = #{class_settings[:reasoning_effort].inspect}" }
    end
    
    app.settings = ActiveSupport::HashWithIndifferentAccess.new(class_settings)
    
    # Debug: Log instance settings after assignment
    if a.name.include?("OpenAI")
      Monadic::Utils::ExtraLogger.log { "#{a.name} instance settings: reasoning_effort = #{app.settings[:reasoning_effort].inspect}" }
    end

    # Evaluate the disabled expression if it's a string containing Ruby code
    if app.settings["disabled"].is_a?(String) && app.settings["disabled"].match?(/defined\?|CONFIG/)
      begin
        app.settings["disabled"] = eval(app.settings["disabled"])
      rescue => e
        # If evaluation fails, assume the app is disabled
        app.settings["disabled"] = true
        Monadic::Utils::ExtraLogger.log { "Warning: Failed to evaluate disabled condition for #{a.name}: #{e.message}" }
      end
    end

    # Evaluate the models expression if it's a string containing Ruby code
    if app.settings["models"].is_a?(String) && app.settings["models"].match?(/defined\?|list_models/)
      begin
        app.settings["models"] = eval(app.settings["models"])
      rescue => e
        # If evaluation fails, use empty array
        app.settings["models"] = []
        Monadic::Utils::ExtraLogger.log { "Warning: Failed to evaluate models for #{a.name}: #{e.message}" }
      end
    end

    # Evaluate the model expression if it's a string containing Ruby code
    if app.settings["model"].is_a?(String) && app.settings["model"].match?(/ENV\[|defined\?|\|\|/)
      begin
        app.settings["model"] = eval(app.settings["model"])
      rescue => e
        # If evaluation fails, use provider default from SSOT
        provider_key = app.settings["provider"] || "openai"
        app.settings["model"] = SystemDefaults.get_default_model(provider_key)
        Monadic::Utils::ExtraLogger.log { "Warning: Failed to evaluate model for #{a.name}: #{e.message}" }
      end
    end

    vendor = app.settings["group"]
    models = app.settings["models"]
    if vendor && models
      MonadicApp.register_models(vendor, models)

      # Validate models against model_spec.js
      invalid_models = []
      Array(models).each do |model_name|
        next if model_name.nil? || model_name.to_s.strip.empty?

        # Normalize and resolve model name
        normalized = Monadic::Utils::ModelSpec.normalize_model_name(model_name.to_s)
        resolved = Monadic::Utils::ModelSpec.resolve_model_alias(model_name.to_s)

        # Check if the resolved model exists in model_spec.js
        unless Monadic::Utils::ModelSpec.model_exists?(resolved)
          invalid_models << model_name.to_s
        end
      end

      unless invalid_models.empty?
        warn_msg = "[WARNING] App '#{app.settings['app_name']}' specifies models not defined in model_spec.js: #{invalid_models.join(', ')}"
        puts warn_msg
        STDERR.puts warn_msg
      end
    end

    app.settings["description"] = app.settings["description"] ? app.settings["description"].dup : ""
    if !app.settings["initial_prompt"]
      app.settings["initial_prompt"] = "You are an AI assistant but the initial prompt is missing. Tell the user they should provide a prompt."
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The initial prompt is missing.</p>"
    end
    if !app.settings["description"] || app.settings["description"].empty?
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The description is missing.</p>"
    end
    if !app.settings["icon"]
      app.settings["icon"] = "<i class='fa-solid fa-circle-question'></i>"
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The icon is missing.</p>"
    end
    if !app.settings["app_name"]
      # Use class name as app_name if not specified (for both rb and mdsl formats)
      app.settings["app_name"] = app.class.name || "UserApp_#{SecureRandom.hex(4)}"
    end
    
    # Set display_name if not specified by converting app_name to readable format
    if !app.settings["display_name"]
      app_name = app.settings["app_name"].to_s
      # Convert camelCase to space-separated words (e.g., 'CodeInterpreterGemini' -> 'Code Interpreter Gemini')
      app.settings["display_name"] = app_name.gsub(/([A-Z])/) { " #{$1}" }.lstrip
    end

    # Don't skip disabled apps - they need to be sent to frontend
    # The frontend will handle the disabled state appropriately
    
    # Register the app regardless of disabled state
    MonadicApp.register_app_settings(app.settings["app_name"], app)
    
    app_name = app.settings["app_name"]

    system_prompt_suffix = DEFAULT_PROMPT_SUFFIX.dup
    prompt_suffix = ""
    response_suffix = ""

    # Always provide code formatting guidance
    system_prompt_suffix << <<~SYSPSUFFIX

    It is important to avoid nesting Markdown code blocks. When embedding the content of a Markdown  file within your response, use the following format. This will ensure that the content is displayed correctly in the browser.

    EXAMPLE_START_HERE
    <div class="language-markdown highlighter-rouge"><pre class="highlight"><code>
    Markdown content here
    </code></pre></div>
    EXAMPLE_END_HERE

    Use backticks to enclose code blocks that are not in Markdown. Make sure to insert a blank line before the opening backticks and after the closing backticks.

    When using Markdown code blocks, always insert a blank line between the code block and the element preceding it.
    SYSPSUFFIX

    if app.settings["tools"]
      # the blank line at the beginning is important!
      system_prompt_suffix << <<~SYSPSUFFIX

        You should NEVER invent or use functions not defined or not listed HERE. If you need to call multiple functions, you will call them one at a time.
      SYSPSUFFIX
    end

    if app.settings["image_generation"]
      # the blank line at the beginning is important!
      response_suffix << <<~RSUFFIX

        <script>
          document.querySelectorAll('.generated_image img').forEach((img) => {
            img.setAttribute('data-action', 'open');
            img.style.cursor = 'pointer';
            img.addEventListener('click', (e) => {
              window.open(e.target.src, '_blank');
            });
          });
        </script>
      RSUFFIX
    end

    if app.settings["mermaid"]
      # the blank line at the beginning is important!
      prompt_suffix << <<~PSUFFIX

        Make sure to follow the format requirement specified in the initial prompt when using Mermaid diagrams. Do not make an inference about the diagram syntax from the previous messages.

        Note that you should not include parentheses in the Mermaid code. For instance, the following code does not render correctly: `A --> B[Prepare Filling (e.g., Ganache or Buttercream)]`
      PSUFFIX
    end

    # the blank line at the beginning is important!
    prompt_suffix = <<~PSUFFIX

      Return your response in the same language as the prompt. If you need to switch to another language, please inform the user.
    PSUFFIX

    if !system_prompt_suffix.empty? || !prompt_suffix.empty? || !response_suffix.empty?
      system_prompt_suffix = "\n\n" + system_prompt_suffix.strip unless system_prompt_suffix.empty?
      prompt_suffix = "\n\n" + prompt_suffix.strip unless prompt_suffix.empty?
      response_suffix = "\n\n" + response_suffix.strip unless response_suffix.empty?

      new_settings = app.settings.dup
      new_settings.merge!(
        {
          "initial_prompt" => "#{new_settings["initial_prompt"]}#{system_prompt_suffix}".strip,
          "prompt_suffix" => "#{new_settings["prompt_suffix"]}#{prompt_suffix}".strip,
          "response_suffix" => "#{new_settings["response_suffix"]}#{response_suffix}".strip
        }
      )
      app.settings = new_settings
    end

    # Skip apps with invalid app_name (nil, empty, or "undefined")
    if app_name.nil? || app_name.to_s.strip.empty? || app_name.to_s == "undefined"
      Monadic::Utils::ExtraLogger.log { "[WARNING] Skipping app with invalid app_name: #{app.class.name}" }
      next
    end

    apps[app_name] = app
  end

  # Load TTS dictionary from provided data, not from a path
  load_tts_dict

  # Group apps by provider and sort alphabetically within each group
  grouped_apps = apps.group_by { |_, app| app.settings["group"] }
  # Sort each group alphabetically by app name
  grouped_apps.each do |group, apps_in_group|
    grouped_apps[group] = apps_in_group.sort_by { |k, _| k }.to_h
  end
  # Flatten the structure back into a single hash
  grouped_apps.values.reduce({}) { |result, group_apps| result.merge(group_apps) }
end

# Load app files and initialize apps
load_app_files
APPS = init_apps

# Configure the Sinatra application
configure do
  # Sessions come from config.ru (Rack::Session::CappedPool). A second
  # session middleware here would replace that session for every route and
  # the WebSocket, and its limits would never apply.
  set :public_folder, "public"
  set :views, "views"
  set :api_key, CONFIG["OPENAI_API_KEY"]
  set :elevenlabs_api_key, CONFIG["ELEVENLABS_API_KEY"]
  enable :cross_origin

  # Configure headers for Electron WebView compatibility. A failed check
  # refuses the request: the default reaction only drops the session and
  # lets the request through, which is no protection for routes that do not
  # use the session.
  set :protection, :except => [:frame_options], :reaction => :deny

  # Add MIME type for WebAssembly files
  mime_type :wasm, 'application/wasm'

  # Disable static file caching in debug mode for development
  if ENV['DEBUG_MODE'] == 'true'
    set :static_cache_control, [:public, :no_cache, :no_store, :must_revalidate]
    puts "🔧 [DEBUG MODE] Static file caching disabled"
  end
end

# Content type mapping for documentation serving (shared across docs routes)
DOCS_CONTENT_TYPE_MAP = {
  ".html" => "text/html",
  ".md" => "text/markdown",
  ".js" => "application/javascript",
  ".css" => "text/css",
  ".json" => "application/json",
  ".png" => "image/png",
  ".jpg" => "image/jpeg",
  ".jpeg" => "image/jpeg",
  ".gif" => "image/gif",
  ".svg" => "image/svg+xml",
  ".ico" => "image/x-icon",
  ".woff" => "font/woff",
  ".woff2" => "font/woff2",
  ".ttf" => "font/ttf",
  ".eot" => "application/vnd.ms-fontobject"
}.freeze

# Load route definitions from separate files
require_relative "monadic/routes/api_routes"
require_relative "monadic/routes/static_routes"
require_relative "monadic/routes/upload_routes"
require_relative "monadic/routes/session_routes"
require_relative "monadic/routes/library_import_routes"
require_relative "monadic/routes/help_routes"
require_relative "monadic/routes/attachment_routes"
require_relative "monadic/routes/shared_folder_routes"
register Monadic::Routes::HelpRoutes
register Monadic::Routes::AttachmentRoutes

# A one-segment URL is a shortcut to a file in the shared folder. Defined
# after every other route: Sinatra matches in order, and defined earlier it
# took GET /monadic_state (the export of a chat's state) as a file name.
get "/:filename" do |filename|
  redirect to("/data/#{filename}")
end


# ──────────────────────────────────────────────────────────────
# Private helper methods (shared across routes)
# ──────────────────────────────────────────────────────────────

def error_json(message)
  { success: false, error: message }.to_json
end

# Note: Signal handling is managed by Falcon server
# Database connections are automatically closed when workers exit
