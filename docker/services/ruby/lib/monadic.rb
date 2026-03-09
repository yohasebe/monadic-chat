# frozen_string_literal: false

# Optimize load path by removing duplicates
$LOAD_PATH.uniq!

require_relative "monadic/utils/document_store_registry"
require_relative "monadic/utils/pdf_storage_config"
require_relative "monadic/utils/ssl_configuration"
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
require "method_source"
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

# Backward compatibility - DEPRECATED
# All tests have been migrated. This can be removed after verifying no external dependencies.
IN_CONTAINER = Monadic::Utils::Environment.in_container?

require_relative "monadic/utils/setup"
require_relative "monadic/utils/tokenizer"
require_relative "monadic/utils/help_embeddings_loader"

require_relative "monadic/utils/string_utils"
helpers StringUtils

require_relative "monadic/utils/interaction_utils"
helpers InteractionUtils

require_relative "monadic/utils/websocket"
helpers WebSocketHelper

require_relative "monadic/utils/pdf_text_extractor"
require_relative "monadic/utils/text_embeddings"
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
require_relative "monadic/adapters/vendors/perplexity_helper"
require_relative "monadic/adapters/vendors/grok_helper"
require_relative "monadic/adapters/vendors/ollama_helper"

envpath = File.expand_path Paths::ENV_PATH
Dotenv.load(envpath)

# Include TavilyHelper for tavily_fetch method
include TavilyHelper

# Connect to the database
begin
  EMBEDDINGS_DB = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
rescue TextEmbeddings::DatabaseError => e
  puts "[WARNING] Failed to initialize help embeddings database: #{e.message}"
  EMBEDDINGS_DB = nil
end

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
  "AUTO_TTS_REALTIME_MODE" => false,  # Default to post-completion mode (false); set to true for realtime TTS during streaming
  "AUTO_TTS_MAX_BYTES" => 400  # Maximum bytes for auto TTS in post-completion mode (default: 400 bytes ≈ 130 Japanese chars or 400 ASCII chars)
}

begin
  # Only process environment variables from the .env file, not dictionary data
  File.read(Paths::ENV_PATH).split("\n").each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")
    
    # Check for valid line format (key=value)
    if !line.include?("=")
      # Skip non-environment variable lines without warning since they might be TTS dictionary entries
      # that should be in a separate file
      next
    end
    
    key, value = line.split("=", 2) # Split only on first '=' to handle values containing '='
    next if key.nil? || key.empty?
    
    # Trim any whitespace and quotes from values
    value = value.strip.gsub(/^['"]|['"]$/, '') if value
    
    # Skip empty API keys
    if key.end_with?("_API_KEY") && (value.nil? || value.empty?)
      next
    end
    
    converted_value = case value
                      when "true"
                        true
                      when "false"
                        false
                      when /^\d+$/ # integer
                        value.to_i
                      when /^\d+\.\d+$/ # float
                        value.to_f
                      when nil
                        # Handle nil value
                        puts "Warning: Empty value for key '#{key}'"
                        next # Skip empty values instead of storing them as empty strings
                      else
                        value
                      end
    CONFIG[key] = converted_value
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

# Configure SSL defaults after environment has been processed
begin
  Monadic::Utils::SSLConfiguration.configure!(CONFIG)
rescue => e
  puts "Warning: Failed to configure SSL defaults: #{e.message}"
end

# Workflow Viewer helpers: extract graph data from app settings
def wv_extract_tools(s)
  pt = s[:progressive_tools] || s["progressive_tools"] || {}
  all_names = pt[:all_tool_names] || pt["all_tool_names"] || []
  always_visible = pt[:always_visible] || pt["always_visible"] || []
  conditional = pt[:conditional] || pt["conditional"] || []
  conditional_map = conditional.each_with_object({}) do |c, h|
    name = c[:name] || c["name"]
    h[name] = {
      visibility: (c[:visibility] || c["visibility"]).to_s,
      unlock_hint: c[:unlock_hint] || c["unlock_hint"]
    }
  end

  all_names.map do |name|
    meta = conditional_map[name]
    {
      name: name,
      visibility: meta ? meta[:visibility] : "always",
      unlock_hint: meta ? meta[:unlock_hint] : nil
    }
  end
end

def wv_extract_shared_tool_groups(s)
  groups = s[:imported_tool_groups] || s["imported_tool_groups"] || []
  groups.map do |g|
    group_name = (g[:name] || g["name"]).to_sym
    tool_names = begin
      MonadicSharedTools::Registry.tools_for(group_name).map(&:name)
    rescue ArgumentError
      []
    end
    {
      name: group_name.to_s,
      visibility: (g[:visibility] || g["visibility"]).to_s,
      tool_count: g[:tool_count] || g["tool_count"] || tool_names.size,
      tool_names: tool_names
    }
  end
end

def wv_extract_agents(s)
  agents = s[:agents] || s["agents"] || {}
  agents.each_with_object({}) do |(k, v), h|
    h[k.to_s] = v.to_s
  end
end

def wv_extract_features(s)
  flags = %w[websearch monadic image pdf jupyter mermaid mathjax abc
             image_generation easy_submit auto_speech initiate_from_assistant]
  result = flags.each_with_object({}) do |f, h|
    val = s[f.to_sym]
    val = s[f] if val.nil?
    h[f] = !!val
  end
  # Normalize: pdf_vector_storage and pdf_upload imply pdf capability
  unless result["pdf"]
    result["pdf"] = !!(s[:pdf_vector_storage] || s["pdf_vector_storage"] || s[:pdf_upload] || s["pdf_upload"])
  end
  result
end

def handle_error(message)
  session[:error] = message
  redirect "/"
end

# List PDF titles in the database with error handling
def list_pdf_titles
  begin
    EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
  rescue StandardError => e
    puts "Error listing PDF titles: #{e.message}"
    []
  end
end

# Determine configured PDF storage mode (ENV), with backward compatibility
def get_pdf_storage_mode
  begin
    changed = Monadic::Utils::PdfStorageConfig.refresh_from_env
    if changed && instance_variable_defined?(:@pdf_storage_mode_cache)
      remove_instance_variable(:@pdf_storage_mode_cache)
    end
  rescue StandardError
    # Ignore refresh errors; fall back to cached value if present.
  end
  return @pdf_storage_mode_cache if instance_variable_defined?(:@pdf_storage_mode_cache)
  begin
    mode = (CONFIG["PDF_STORAGE_MODE"] || CONFIG["PDF_DEFAULT_STORAGE"] || 'local').to_s.downcase
    @pdf_storage_mode_cache = %w[local cloud].include?(mode) ? mode : 'local'
  rescue StandardError
    @pdf_storage_mode_cache = 'local'
  end
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
  if Dir.exist?(user_apps_dir)
    Dir["#{File.join(user_apps_dir, "**") + File::SEPARATOR}*.{rb,mdsl}"].sort.each do |file|
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
  Monadic::Utils::ExtraLogger.log { "Debug: environment has DISTRIBUTED_MODE=#{ENV["DISTRIBUTED_MODE"]}" }
  
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

    if app.settings["pdf_vector_storage"]
      # Ensure common local PDF tools are available for apps that opted in
      begin
        app.settings["tools"] ||= []
        existing = app.settings["tools"].map { |t| (t.respond_to?(:[]) ? (t["function"] && t["function"]["name"]) : nil) }.compact

        defn = lambda do |name, desc, params|
          {
            "type" => "function",
            "function" => {
              "name" => name,
              "description" => desc,
              "parameters" => {
                "type" => "object",
                "properties" => params.transform_values { |spec| { "type" => spec } },
                "required" => params.keys
              }
            }
          }
        end

        common_tools = []
        common_tools << defn.call("find_closest_text", "Find the closest text snippets in local PDF database", { "text" => "string", "top_n" => "integer" })
        common_tools << defn.call("get_text_snippet", "Retrieve one text snippet from a document by position", { "doc_id" => "integer", "position" => "integer" })
        common_tools << defn.call("list_titles", "List all document titles in local PDF database", {})
        common_tools << defn.call("find_closest_doc", "Find the closest documents in local PDF database", { "text" => "string", "top_n" => "integer" })
        common_tools << defn.call("get_text_snippets", "Retrieve all snippets of a document", { "doc_id" => "integer" })

        common_tools.each do |tool|
          name = tool.dig("function", "name")
          next if existing.include?(name)
          app.settings["tools"] << tool
        end
      rescue StandardError
        # non-fatal
      end
      # Add document search policy hint (no hybrid mode)
      begin
        configured_mode = get_pdf_storage_mode
        storage_desc = (configured_mode == 'cloud') ? 'Cloud File Search (OpenAI Vector Store)' : 'Local PDF Database (functions)'
        system_prompt_suffix << <<~SYSPSUFFIX

          DOCUMENT SEARCH POLICY:
          - Your document source is: #{storage_desc}.
          - Use it when the user asks to reference their PDFs or knowledge base.
          - If no relevant results are found, explain the limitation briefly.

          When citing results, include a compact metadata footer after an `---` divider with:
          Doc Title, Snippet tokens, and Snippet position.
        SYSPSUFFIX
      rescue StandardError
        # Non-fatal if mode cannot be determined here
      end
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

  # Filter out Jupyter apps if we're in server mode unless explicitly allowed
  distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] || "off"
  allow_jupyter_in_server = CONFIG["ALLOW_JUPYTER_IN_SERVER_MODE"] == true || CONFIG["ALLOW_JUPYTER_IN_SERVER_MODE"] == "true"
  
  if distributed_mode == "server" && !allow_jupyter_in_server
    # Create a new hash without the Jupyter apps
    filtered_apps = {}
    apps.each do |app_name, app|
      settings = app.settings
      if settings["jupyter"] == true ||
         settings["jupyter"] == "true" ||
         app_name.to_s.downcase.include?("jupyter") ||
         settings["display_name"].to_s.downcase.include?("jupyter")
        Monadic::Utils::ExtraLogger.log { "Filtering out Jupyter app in server mode: #{app_name}" }
      else
        filtered_apps[app_name] = app
      end
    end
    apps = filtered_apps
    puts "SERVER MODE: Filtered out Jupyter apps for security reasons (set ALLOW_JUPYTER_IN_SERVER_MODE=true in config to enable)"
  elsif distributed_mode == "server" && allow_jupyter_in_server
    puts "SERVER MODE: Jupyter apps enabled via ALLOW_JUPYTER_IN_SERVER_MODE configuration"
  end

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
  use Rack::Session::Pool
  set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
  set :public_folder, "public"
  set :views, "views"
  set :api_key, CONFIG["OPENAI_API_KEY"]
  set :elevenlabs_api_key, CONFIG["ELEVENLABS_API_KEY"]
  enable :cross_origin

  # Configure headers for Electron WebView compatibility
  set :protection, :except => [:frame_options]

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
require_relative "monadic/routes/pdf_routes"
require_relative "monadic/routes/api_routes"
require_relative "monadic/routes/static_routes"
require_relative "monadic/routes/upload_routes"
require_relative "monadic/routes/session_routes"

APPS.each do |k, v|
  # convert `k` from a capitalized multi word title to snake_case
  # e.g., `Monadic App` to `monadic_app`
  endpoint = k.to_s.gsub(/\s+/, "_").downcase

  get "/#{endpoint}" do
    session[:messages] = []
    if session[:websocket_session_id]
      WebSocketHelper.update_session_state(
        session[:websocket_session_id],
        messages: session[:messages],
        parameters: session[:parameters]
      )
    end
    parameters = v.settings.dup
    
    
    session[:parameters] = parameters
    redirect "/"
  end
end

# ──────────────────────────────────────────────────────────────
# Private helper methods (shared across routes)
# ──────────────────────────────────────────────────────────────

def error_json(message)
  { success: false, error: message }.to_json
end

def resolve_openai_app_key
  (session[:parameters] && session[:parameters]["app_name"]) || "default"
rescue StandardError
  "default"
end

def openai_pdf_headers(api_key)
  headers = { "Authorization" => "Bearer #{api_key}", "OpenAI-Beta" => "assistants=v2" }
  api_base = "https://api.openai.com/v1"
  [headers, api_base]
end

def vs_meta_path
  File.join(Monadic::Utils::Environment.data_path, "pdf_navigator_openai.json")
end

def bump_pdf_cache_version
  session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
rescue StandardError
  # no-op
end

def resolve_vector_store_id(app_key)
  # Priority: session → app-specific ENV → global ENV → registry → fallback meta
  app_env_vs = begin
    key = "OPENAI_VECTOR_STORE_ID__#{app_key.upcase}"
    val = CONFIG[key]
    s = val.to_s.strip
    s.empty? ? nil : s
  rescue StandardError
    nil
  end
  reg_vs_id = begin
    Monadic::Utils::DocumentStoreRegistry.get_app(app_key).dig('cloud', 'vector_store_id')
  rescue StandardError
    nil
  end
  env_vs_id = CONFIG["OPENAI_VECTOR_STORE_ID"].to_s.strip if CONFIG.key?("OPENAI_VECTOR_STORE_ID")
  fallback_vs = nil
  if File.exist?(vs_meta_path)
    begin
      meta = JSON.parse(File.read(vs_meta_path))
      fallback_vs = meta["vector_store_id"]
    rescue StandardError
      fallback_vs = nil
    end
  end
  vs_id = session[:openai_vector_store_id]
  vs_id = app_env_vs if (vs_id.nil? || vs_id.empty?) && app_env_vs
  vs_id = env_vs_id if (vs_id.nil? || vs_id.empty?) && env_vs_id && !env_vs_id.empty?
  vs_id = reg_vs_id if (vs_id.nil? || vs_id.empty?) && reg_vs_id
  vs_id = fallback_vs if (vs_id.nil? || vs_id.empty?) && fallback_vs
  # Keep session in sync for downstream usage
  session[:openai_vector_store_id] = vs_id if vs_id
  vs_id
end

# Note: Signal handling is managed by Falcon server
# Database connections are automatically closed when workers exit
