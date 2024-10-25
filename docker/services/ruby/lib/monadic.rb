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

require "oj"
Oj.mimic_JSON

# return true if we are inside a docker container
IN_CONTAINER = File.file?("/.dockerenv")

require_relative "monadic/version"

require_relative "monadic/utils/setup"
require_relative "monadic/utils/flask_app_client"

require_relative "monadic/utils/string_utils"
helpers StringUtils

require_relative "monadic/utils/openai_utils"
helpers OpenAIUtils

require_relative "monadic/utils/websocket"
helpers WebSocketHelper

require_relative "monadic/utils/pdf_text_extractor"
require_relative "monadic/utils/text_embeddings"

require_relative "monadic/monadic_app"

envpath = File.expand_path Paths::ENV_PATH
Dotenv.load(envpath)

# Connect to the database
EMBEDDINGS_DB = TextEmbeddings.new("monadic", recreate_db: false)

CONFIG = {}

begin
  File.read(Paths::ENV_PATH).split("\n").each do |line|
    key, value = line.split("=")
    CONFIG[key] = value
  end
rescue StandardError => e
  CONFIG["ERROR"] = e.message
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
    apps_to_load[File.basename(file)] = file
  end

  if Dir.exist?(user_plugins_dir)
    Dir["#{File.join(user_plugins_dir, "**", "apps", "**") + File::SEPARATOR}*.rb"].sort.each do |file|
      apps_to_load[File.basename(file)] = file
    end
  end

  apps_to_load.each_value do |file|
    require file
  end
end

# Initialize apps
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")
  klass.subclasses.each do |a|
    app = a.new
    app.settings = ActiveSupport::HashWithIndifferentAccess.new(a.instance_variable_get(:@settings))

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

    initial_prompt_suffix = ""
    prompt_suffix = ""
    response_suffix = ""

    if app.settings["mathjax"]
      # the blank line at the beginning is important!
      initial_prompt_suffix << <<~INITIAL

        You use the MathJax notation to write mathematical expressions. In doing so, you should follow the format requirements: Use double dollar signs `$$` to enclose MathJax/LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly.
      INITIAL

      if app.settings["monadic"] || app.settings["jupyter"]
        # the blank line at the beginning is important!
        initial_prompt_suffix << <<~INITIAL

        Make sure to escape properly in the MathJax expressions.

        Good examples of inline MathJax expressions:
        - `$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$`
        - `$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$`
        - `$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$`
        - `$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$`

        Good examples of block MathJax expressions:
        - `$$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$$`
        - `$$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
        - `$$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$$`
        - `$$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$$`
        INITIAL
      else
        # the blank line at the beginning is important!
        initial_prompt_suffix << <<~INITIAL

        Good examples of inline MathJax expressions:
        - `$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$`
        - `$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$`
        - `$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$`
        - `$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$`

        Good examples of block MathJax expressions:
        - `$$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$$`
        - `$$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
        - `$$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$$`
        - `$$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$$`

        Remember that the following are not available in MathJax:
        - `\begin{itemize}` and `\end{itemize}`
        INITIAL
      end

      prompt_suffix << <<~SUFFIX
      Use double dollar signs `$$` to enclose MathJax/LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly.
      SUFFIX
    end

    if app.settings["tools"]
      # the blank line at the beginning is important!
      initial_prompt_suffix << <<~INITIAL

        You should NEVER invent or use functions not defined or not listed HERE. If you need to call multiple functions, you will call them one at a time.
      INITIAL
    end

    if app.settings["image_generation"]
      # the blank line at the beginning is important!
      response_suffix << <<~INITIAL

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
      INITIAL
    end

    if app.settings["pdf"]
      app.embeddings_db = EMBEDDINGS_DB
    end

    if app.settings["mermaid"]
      # the blank line at the beginning is important!
      prompt_suffix << <<~INITIAL

        Make sure to follow the format requirement specified in the initial prompt when using Mermaid diagrams. Do not make an inference about the diagram syntax from the previous messages.
      INITIAL
    end

    # the blank line at the beginning is important!
    prompt_suffix = <<~SUFFIX

      Return your response in the same language as the prompt. If you need to switch to another language, please inform the user.
    SUFFIX

    if !initial_prompt_suffix.empty? || !prompt_suffix.empty? || !response_suffix.empty?
      initial_prompt_suffix = "\n\n" + initial_prompt_suffix.strip unless initial_prompt_suffix.empty?
      prompt_suffix = "\n\n" + prompt_suffix.strip unless prompt_suffix.empty?
      response_suffix = "\n\n" + response_suffix.strip unless response_suffix.empty?

      new_settings = app.settings.dup
      new_settings.merge!(
        {
          "initial_prompt" => "#{new_settings["initial_prompt"]}#{initial_prompt_suffix}".strip,
          "prompt_suffix" => "#{new_settings["prompt_suffix"]}#{prompt_suffix}".strip,
          "response_suffix" => "#{new_settings["response_suffix"]}#{response_suffix}".strip
        }
      )
      app.settings = new_settings
    end

    apps[app_name] = app
  end
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
          html = markdown_to_html(text)
        end
        message_obj = { "role" => msg["role"], "text" => text, "html" => html, "lang" => detect_language(text), "mid" => msg["mid"], "active" => true }
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

# Upload a PDF file
post "/pdf" do
  if params["pdfFile"]
    pdf_file_handler = params["pdfFile"]["tempfile"]
    # Create a temporary file and write the content of the file handler to it
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
  puts "\nTerminating the application..."
  EMBEDDINGS_DB.close_connection
  exit
end
