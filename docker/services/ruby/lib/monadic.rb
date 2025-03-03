# frozen_string_literal: false

require "active_support"
require "active_support/core_ext/hash/indifferent_access"
require "base64"
require "cld"
require "digest"
require "dotenv"
require "eventmachine"
require "faye/websocket"
require "http"
require "http/form_data"
require "httparty"
require "i18n_data"
require "json"
require "kramdown"
require "kramdown-parser-gfm"
require "method_source"
require "net/http"
require "nokogiri"
require "open3"
require "pragmatic_segmenter"
require "rouge"
require "securerandom"
require "strscan"
require "tempfile"
require "uri"
require "cgi"
require "yaml"
require "csv"

$MODELS = {}

# return true if we are inside a docker container
IN_CONTAINER = File.file?("/.dockerenv")

require_relative "monadic/version"

require_relative "monadic/utils/setup"
require_relative "monadic/utils/flask_app_client"

require_relative "monadic/utils/string_utils"
helpers StringUtils

require_relative "monadic/utils/interaction_utils"
helpers InteractionUtils

require_relative "monadic/utils/websocket"
helpers WebSocketHelper

require_relative "monadic/utils/pdf_text_extractor"
require_relative "monadic/utils/text_embeddings"

require_relative "monadic/monadic_app"

envpath = File.expand_path Paths::ENV_PATH
Dotenv.load(envpath)

# Connect to the database
EMBEDDINGS_DB = TextEmbeddings.new("monadic", recreate_db: false)

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

CONFIG = {}

begin
  File.read(Paths::ENV_PATH).split("\n").each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")
    
    # Check for valid line format (key=value)
    if !line.include?("=")
      puts "Warning: Skipping invalid environment line: #{line}"
      next
    end
    
    key, value = line.split("=", 2) # Split only on first '=' to handle values containing '='
    next if key.nil? || key.empty?
    
    # Trim any whitespace and quotes from values
    value = value.strip.gsub(/^['"]|['"]$/, '') if value
    
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
                        ""
                      else
                        value
                      end
    CONFIG[key] = converted_value
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

def handle_error(message)
  session[:error] = message
  redirect "/"
end

# list PDF titles in the database
def list_pdf_titles
  EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
end

# Load app files
def load_app_files
  apps_to_load = {}
  base_app_dir = File.join(__dir__, "..", "apps")
  user_plugins_dir = if IN_CONTAINER
                   "/monadic/data/plugins"
                 else
                   Dir.home + "/monadic/data/plugins"
                 end

  Dir["#{File.join(base_app_dir, "**") + File::SEPARATOR}*.rb"].sort.each do |file|
    basename = File.basename(file)
    next if basename.start_with?("_") # ignore files that start with an underscore
    apps_to_load[basename] = file
  end

  if Dir.exist?(user_plugins_dir)
    Dir["#{File.join(user_plugins_dir, "**", "apps", "**") + File::SEPARATOR}*.rb"].sort.each do |file|
      basename = File.basename(file)
      next if basename.start_with?("_") # ignore files that start with an underscore
      apps_to_load[File.basename(file)] = file
    end
  end

  apps_to_load.each_value do |file|
    require file
  end
end

# load the TTS dictionary, which is a valid CSV of [original, replacement] pairs
def load_tts_dict(tts_dict_path)
  if File.exist?(tts_dict_path)
    tts_dict = {}
    begin
      CSV.foreach(tts_dict_path, headers: false) do |row|
        # make sure the data is in UTF-8; otherwise, convert it
        row.map! { |r| r.encode("UTF-8", invalid: :replace, undef: :replace, replace: "") }
        tts_dict[row[0]] = row[1]
      end
    rescue StandardError => e
    end
  end
  CONFIG["TTS_DICT"] = tts_dict
end

# Initialize apps
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")
  klass.subclasses.each do |a|
    app = a.new
    app.settings = ActiveSupport::HashWithIndifferentAccess.new(a.instance_variable_get(:@settings))

    vendor = app.settings["group"]
    models = app.settings["models"]
    if vendor && models
      MonadicApp.register_models(vendor, models)
    end

    MonadicApp.register_app_settings(app.settings["app_name"], app)

    app.settings["description"] ||= ""
    if !app.settings["initial_prompt"]
      app.settings["initial_prompt"] = "You are an AI assistant but the initial prompt is missing. Tell the user they should provide a prompt."
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The initial prompt is missing.</p>"
    end
    if !app.settings["description"]
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The description is missing.</p>"
    end
    if !app.settings["icon"]
      app.settings["icon"] = "<i class='fa-solid fa-circle-question'></i>"
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The icon is missing.</p>"
    end
    if !app.settings["app_name"]
      app.settings["app_name"] = "User App (#{SecureRandom.hex(4)})"
      app.settings["description"] << "<p><i class='fa-solid fa-triangle-exclamation'></i> The app name is missing.</p>"
    end

    next if app.settings["disabled"]

    app_name = app.settings["app_name"]

    system_prompt_suffix = DEFAULT_PROMPT_SUFFIX.dup
    prompt_suffix = ""
    response_suffix = ""

    if app.settings["sourcecode"]
      system_prompt_suffix << <<~SYSPSUFFIX

      It is important to avoid nesting Markdown code blocks. When embedding the content of a Markdown  file within your response, use the following format. This will ensure that the content is displayed correctly in the browser. 

      EXAMPLE_START_HERE
      <div class="language-markdown highlighter-rouge”><pre class=“highlight”><code>
      Markdown content here
      </code></pre></div>
      EXAMPLE_END_HERE

      Use backticks to enclose code blocks that are not in Markdown. Make sure to insert a blank line before the opening backticks and after the closing backticks.

      When using Markdown code blocks, always insert a blank line between the code block and the element preceding it.
      SYSPSUFFIX
    end

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
            img.addEventListener('click', (e) => {
              window.open(e.target.src, '_blank');
            });
          });
          document.querySelectorAll('.generated_image img').forEach((img) => {
            img.style.cursor = 'pointer';
          });
        </script>
      RSUFFIX
    end

    if app.settings["pdf"]
      app.embeddings_db = EMBEDDINGS_DB
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

    apps[app_name] = app
  end

  load_tts_dict(CONFIG["TTS_DICT_PATH"]) if CONFIG["TTS_DICT_PATH"]

  # remove apps if its settings are empty
  apps.sort_by { |k, _v| k }.to_h
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
  set :api_key, ENV["OPENAI_API_KEY"]
  set :elevenlabs_api_key, ENV["ELEVENLABS_API_KEY"]
  enable :cross_origin
end

# Accept requests from the client
get "/" do
  @timestamp = Time.now.to_i
  session[:parameters] ||= {}
  session[:messages] ||= []
  session[:version] = Monadic::VERSION
  session[:docker] = IN_CONTAINER

  if Faye::WebSocket.websocket?(env)
    websocket_handler(env)
  else
    erb :index
  end
end

def fetch_file(file_name)
  datadir = if IN_CONTAINER
              File.expand_path(File.join(__dir__, "..", "data"))
            else
              File.expand_path(File.join(Dir.home, "monadic", "data"))
            end
  file_path = File.join(datadir, file_name)
  if File.exist?(file_path)
    send_file file_path
  else
    "Sorry, the file you are looking for is unavailable."
  end
end

# Convert a string to a integer
def string_to_int(str)
  hash = Digest::SHA256.hexdigest(str)
  int_value = hash[0..7].to_i(16) % 2_147_483_648 # 0 to 2,147,483,647
  int_value -= 2_147_483_648 if int_value > 1_073_741_823
  int_value
end

get "/monadic/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/lab/?" do
  url = "http://127.0.0.1:8889/lab/"
  result = HTTParty.get(url)
  status result.code
  result.body
end

get "/lab/*" do
  url = "http://127.0.0.1:8889/lab/#{params["splat"].first}"
  result = HTTParty.get(url)
  status result.code
  result.body
end

get "/:filename" do |filename|
  redirect to("/data/#{filename}")
end

# Accept requests from the client to provide language codes and country names
get "/lctags" do
  languages = I18nData.languages
  countries = I18nData.countries
  content_type :json
  return { "languages" => languages, "countries" => countries }.to_json
end

# Upload a Session JSON file to load past messages
post "/load" do
  if params[:file]
    begin
      file = params[:file][:tempfile]
      content = file.read
      json_data = JSON.parse(content)
      session[:status] = "loaded"
      session[:parameters] = json_data["parameters"]

      # Check if the first message is a system message
      if json_data["messages"].first && json_data["messages"].first["role"] == "system"
        session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
      end

      session[:messages] = json_data["messages"].uniq.map do |msg|
        if json_data["parameters"]["monadic"].to_s == "true" && msg["role"] == "assistant"
          text = msg["text"]
          html = APPS[json_data["parameters"]["app_name"]].monadic_html(msg["text"])
        else
          text = msg["text"]
          html = text
        end
        message_obj = { "role" => msg["role"], "text" => text, "html" => html, "lang" => detect_language(text), "mid" => msg["mid"], "active" => true }
        message_obj["thinking"] = msg["thinking"] if msg["thinking"]
        message_obj["images"] = msg["images"] if msg["images"]
        message_obj
      end
    rescue JSON::ParserError
      handle_error("Error: Invalid JSON file. Please upload a valid JSON file.")
    end
  else
    handle_error("Error: No file selected. Please choose a JSON file to upload.")
  end
  redirect "/"
end

# Convert a document file to text
post "/document" do
  if params["docFile"]
    doc_file_handler = params["docFile"]["tempfile"]
    # name the file based on datetime if no title is provided
    doc_label = params["docLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    # get filename from the file handler
    filename = params["docFile"]["filename"]

    user_data_dir = if IN_CONTAINER
                      "/monadic/data"
                    else
                      Dir.home + "/monadic/data"
                    end

    # Copy the file to user data directory
    doc_file_path = File.join(user_data_dir, filename)
    File.open(doc_file_path, "wb") do |f|
      f.write(doc_file_handler.read)
    end

    utf8_filename = File.basename(doc_file_path).force_encoding("UTF-8")
    doc_file_handler.close

    markdown = MonadicApp.doc2markdown(utf8_filename)

    doc_text = "Filename: " + utf8_filename + "\n---\n" + markdown
    if doc_label.to_s != ""
      "\n---\n" + doc_label + "\n---\n" + doc_text
    else
      "\n---\n" + doc_text
    end
  else
    session[:error] = "Error: No file selected. Please choose a document file to convert."
  end
end


# Fetch the webpage content
post "/fetch_webpage" do
  if params["pageURL"]
    url = params["pageURL"]
    url_decoded = CGI.unescape(url)
    label = params["urlLabel"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    user_data_dir = if IN_CONTAINER
                      "/monadic/data"
                    else
                      Dir.home + "/monadic/data"
                    end

    tavily_api_key = CONFIG["TAVILY_API_key"]
    if tavily_api_key
      markdown = tavily_fetch(url: url)
    else
      markdown = MonadicApp.fetch_webpage(url)
    end

    webpage_text = "URL: " + url_decoded + "\n---\n" + markdown
    if label.to_s != ""
      "---\n" + label + "\n---\n" + webpage_text
    else
      "---\n" + webpage_text
    end
  else
    session[:error] = "Error: No file selected. Please choose a document file to convert."
  end
end

# Upload a PDF file
post "/pdf" do
  if params["pdfFile"]
    pdf_file_handler = params["pdfFile"]["tempfile"]
    temp_file = Tempfile.new("temp_pdf")
    temp_file.binmode
    temp_file.write(pdf_file_handler.read)
    temp_file.rewind

    # Close the original file handler
    pdf_file_handler.close

    pdf = PDF2Text.new(path: temp_file.path, max_tokens: 800, separator: "\n", overwrap_lines: 2)
    pdf.extract

    # Close and delete the temporary file
    temp_file.close
    temp_file.unlink

    doc_data = { items: 0, metadata: {} }
    items_data = []

    pdf.split_text.each do |i|
      title = if params["pdfTitle"].to_s != ""
                params["pdfTitle"]
              else
                params["pdfFile"]["filename"]
              end

      doc_data[:title] = title
      doc_data[:items] += 1

      items_data << { text: i["text"], metadata: { tokens: i["tokens"] } }
    end
    EMBEDDINGS_DB.store_embeddings(doc_data, items_data, api_key: settings.api_key)
    return params["pdfFile"]["filename"]
  else
    session[:error] = "Error: No file selected. Please choose a PDF file to upload."
  end
end

# Create endpoints for each app in the APPS hash
APPS.each do |k, v|
  # convert `k` from a capitalized multi word title to snake_case
  # e.g., `Monadic App` to `monadic_app`
  endpoint = k.to_s.gsub(/\s+/, "_").downcase

  get "/#{endpoint}" do
    session[:messages] = []
    session[:parameters] = v.settings
    redirect "/"
  end
end

# Capture the INT signal (e.g., when pressing Ctrl+C)
Signal.trap("INT") do
  puts "\nTerminating the application . . ."
  EMBEDDINGS_DB.close_connection
  exit
end
