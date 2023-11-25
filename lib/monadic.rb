# frozen_string_literal: true

require "cld"
require "dotenv"
require "eventmachine"
require "faye/websocket"
require "http"
require "http/form_data"
require "i18n_data"
require "json"
require "kramdown"
require "kramdown-parser-gfm"
require "method_source"
require "nokogiri"
require "net/http"
require "pragmatic_segmenter"
require "rouge"
require "securerandom"
require "strscan"
require "tempfile"
require "tiktoken_ruby"
require "uri"

require_relative "embeddings/pdf_text_extractor"
require_relative "embeddings/text_embeddings"
require_relative "monadic/monadic_app"
require_relative "monadic/version"

require_relative "helpers/openai"
helpers OpenAIHelper

require_relative "helpers/websocket"
helpers WebSocketHelper

require_relative "helpers/utilities"
helpers UtilitiesHelper

envpath = File.expand_path OpenAIHelper::ENV_PATH
Dotenv.load(envpath)

# Connect to the database
EMBEDDINGS_DB = TextEmbeddings.new("monadic", recreate_db: false)

# list PDF titles in the database
def list_pdf_titles
  EMBEDDINGS_DB.list_titles
end

# Load app files
def load_app_files
  Dir["#{File.join(__dir__, "..", "apps", "**") + File::SEPARATOR}*.rb"].sort.each do |file|
    require file
  end
end

# Initialize apps
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")
  klass.subclasses.each do |app|
    app = app.new
    app_name = app.settings[:app_name]
    apps[app_name] = app
  end
  apps.sort_by { |k, _v| k }.to_h
end

# Load app files and initialize apps
load_app_files
APPS = init_apps

# Configure the Sinatra application
configure do
  use Rack::Session::Pool, expire_after: 86_400
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

# Accept requests from the client to provide language codes and country names
get "/lctags" do
  languages = I18nData.languages
  countries = I18nData.countries
  content_type :json
  return { "languages" => languages, "countries" => countries }.to_json
end

# Upload a JSON file to load past messages
post "/load" do
  if params[:file]
    begin
      file = params[:file][:tempfile]
      content = file.read
      json_data = JSON.parse(content)
      session[:status] = "loaded"
      session[:parameters] = json_data["parameters"]
      session[:messages] = json_data["messages"].uniq.map do |msg|
        if json_data["parameters"]["monadic"].to_s == "true" && msg["role"] == "assistant"
          text = msg["text"]
          html = APPS[json_data["parameters"]["app_name"]].monadic_html(msg["text"])
        else
          text = msg["text"]
          html = markdown_to_html(text)
        end
        { "role" => msg["role"], "text" => text, "html" => html, "lang" => detect_language(text), "mid" => msg["mid"], "active" => true }
      end
    rescue JSON::ParserError
      session[:error] = "Error: Invalid JSON file. Please upload a valid JSON file."
    end
  else
    session[:error] = "Error: No file selected. Please choose a JSON file to upload."
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

    # Use the temporary file path to extract the text using the poppler gem
    pdf = PDF2Text.new(path: temp_file.path, max_tokens: 800, separator: "\n", overwrap_lines: 2)
    pdf.extract

    # Close and delete the temporary file
    temp_file.close
    temp_file.unlink
    pdf.split_text.each do |segment|
      # if params["pdfTitle"] does not exist, use the title
      title = if params["pdfTitle"].to_s != ""
                params["pdfTitle"]
              else
                params["pdfFile"]["filename"]
              end
      segment["title"] = title
      EMBEDDINGS_DB.store_embeddings(segment["text"], segment, api_key: settings.api_key)
    end
    return params["pdfFile"]["filename"]
  else
    session[:error] = "Error: No file selected. Please choose a PDF file to upload."
  end
end

# Create endpoints for each app in the APPS hash
APPS.each do |k, v|
  # convert `k` from a capitalized multi word title to snake_case
  # e.g., `Monadic App` to `monadic_app`
  endpoint = k.gsub(/\s+/, "_").downcase
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
